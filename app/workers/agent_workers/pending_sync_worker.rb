module AgentWorkers
  ##
  # Replays dropped agent writes (`agent_pending_syncs`, see Agent::PendingSync).
  #
  # Each row only says "(region, subject, kind, key) is out of sync"; the body is
  # recomputed from CURRENT data through the ordinary live call site, so nothing stale
  # is ever replayed.
  #
  # Triggers: lib/clock.rb every minute (no args: fans out one job per region with due
  # rows), a node leaving maintenance, a node coming back online, and the AZ page's
  # "Retry dead" action.
  #
  # Per region, under an advisory lock so passes never overlap:
  # - resolve a node like Agent::Client (online, else not disconnected). None: skip the
  #   region entirely -- no attempt is counted and no age accrues;
  # - firewall, then tenant_delete, then tenant, then the managed kinds, at most
  #   BATCH rows;
  # - at the first transport failure, stop: the agent is unreachable, so the remaining
  #   rows are pushed back a minute without counting an attempt. The row that hit it
  #   backs off and records the error, but a transport failure never counts toward
  #   dead either: only an agent that ANSWERED and refused (non-2xx, false, NotReady)
  #   does. A long outage still raises the stale SystemEvent, which ages rows from
  #   when the drop was recorded.
  #
  # Per row, every write is guarded by the generation read before the body is computed,
  # so a drop recorded concurrently is never deleted or overwritten by this pass.
  class PendingSyncWorker
    include Sidekiq::Worker
    sidekiq_options retry: false, queue: "default"

    ADVISORY_LOCK_CLASS = 0x63730003
    BATCH = 50
    MAX_ATTEMPTS = 24
    MAX_AGE = 48.hours
    MAX_BACKOFF = 30.minutes
    TRANSPORT_DEFER = 1.minute
    # A live row this long past its recorded drop (first_failed_at) raises a SystemEvent...
    STALE_AFTER = 1.hour
    # ...at most once per region per window.
    STALE_ALERT_WINDOW = 6.hours

    TRANSPORT_ERRORS = [Errno::ECONNREFUSED, SocketError, HTTP::Error].freeze

    # @param region_id [Integer, nil] nil fans out over every region with due rows
    def perform(region_id = nil)
      if region_id.nil?
        due_scope.distinct.pluck(:region_id).each { |rid| self.class.perform_async(rid) }
        return
      end
      region = Region.find_by(id: region_id)
      return if region.nil?
      with_lock(region.id) { process_region(region) }
    end

    # @param region [Region]
    def process_region(region)
      node = region.nodes.online.first || region.nodes.where(disconnected: false).first
      return if node.nil?

      rows = due_scope.where(region_id: region.id).order(Arel.sql(order_sql), :id).limit(BATCH).to_a
      rows.each_with_index do |row, i|
        next unless process_row(row, region, node) == :transport
        rest = rows[(i + 1)..].map(&:id)
        AgentPendingSync.where(id: rest, dead_at: nil).update_all(next_attempt_at: TRANSPORT_DEFER.from_now) if rest.any?
        break
      end
      report_stale!(region)
    end

    private

    def due_scope
      AgentPendingSync.where(dead_at: nil).where(next_attempt_at: ..Time.current)
    end

    def order_sql
      whens = Agent::PendingSync::ORDER.each_with_index.map { |k, i| "WHEN '#{k}' THEN #{i}" }.join(" ")
      "CASE kind #{whens} ELSE #{Agent::PendingSync::ORDER.size} END"
    end

    # @return [Symbol] :ok, :failed, :transport, :skipped, :dropped
    def process_row(row, region, node)
      # Re-read: a concurrent record! may have bumped the generation, or a deprovision
      # may have deleted the row, since the batch was selected.
      row = AgentPendingSync.find_by(id: row.id)
      return :skipped if row.nil? || row.dead_at
      gen = row.generation

      push = resolve(row, region, node)
      case push
      when :drop
        AgentPendingSync.where(id: row.id, generation: gen).delete_all
        return :dropped
      when :skip
        return :skipped
      end

      ok = Agent::Client.raising_transport_errors { push.call }
      if ok
        if row.kind == "tenant_delete"
          Agent::TenantRegistry.deprovisioned!(row.project_id, row.region_id)
        else
          AgentPendingSync.where(id: row.id, generation: gen).delete_all
        end
        :ok
      else
        fail!(row, gen, "agent did not accept the #{row.kind} push")
        :failed
      end
    rescue *TRANSPORT_ERRORS => e
      fail!(row, gen, "#{e.class}: #{e.message}", transport: true) if row && gen
      :transport
    rescue Agent::Client::NotReady => e
      fail!(row, gen, "#{e.class}: #{e.message}") if row && gen
      :failed
    rescue => e
      ExceptionAlertService.new(e, "e3b7a0d5c91f2486").perform
      fail!(row, gen, "#{e.class}: #{e.message}") if row && gen
      :failed
    end

    # Resolve the row's subject against current data.
    # @return [Proc, :drop, :skip] the push to run, or what to do instead
    def resolve(row, region, node)
      case row.kind
      when "firewall"
        fw_node = Node.find_by(id: row.node_id)
        return :drop if fw_node.nil? || fw_node.region_id != row.region_id
        # Firewall rules go to their own node, not the region's resolved one. One that is
        # disconnected is skipped like a region without a node: no attempt, no age.
        return :skip if fw_node.disconnected
        -> { fw_node.update_iptable_config!(record_drop: false) }
      when "tenant_delete"
        -> { Agent::Client.for_project_id(row.project_id, region: region).deprovision_tenant! }
      else
        project = Deployment.find_by(id: row.project_id)
        return :drop if project.nil? || Agent::TenantRegistry.deleting?(project.id)
        project_region = project.region
        return :drop if project_region.nil? || project_region.id != row.region_id
        case row.kind
        when "tenant"
          -> { Agent::Client.new(project, region: region, node: node).provision_tenant! }
        when "managed_metadata"
          -> { ProjectServices::StoreMetadata.new(project).perform(record_drop: false, self_heal: false) }
        when "managed_ssh_keys"
          -> { ProjectServices::MetadataSshKeys.new(project).perform(record_drop: false, self_heal: false) }
        when "managed_sftp_host_keys"
          sftp = Deployment::Sftp.find_by(name: row.key, deployment_id: row.project_id)
          return :drop if sftp.nil?
          sftp_region = sftp.region
          return :drop if sftp_region.nil? || sftp_region.id != row.region_id
          -> { SftpServices::MetadataSshHostKeys.new(sftp).perform(record_drop: false, self_heal: false) }
        else
          :drop
        end
      end
    end

    # A real attempt failed. Backoff 2^attempts minutes (capped), dead after MAX_ATTEMPTS
    # attempts or MAX_AGE since the first REAL attempt, all at the generation read before
    # the push: a newer drop already reset the row for an immediate retry.
    #
    # transport: the agent was never reached. The row retries after the first backoff step and records
    # the error, but neither counts an attempt nor starts the dead clock.
    def fail!(row, gen, error, transport: false)
      now = Time.current
      attempts = row.attempts + 1
      if transport
        backoff = [(2**attempts).minutes, MAX_BACKOFF].min
        AgentPendingSync.where(id: row.id, generation: gen, dead_at: nil).update_all(
          last_attempt_at: now,
          last_error: error.to_s.truncate(2000),
          next_attempt_at: now + backoff,
          updated_at: now
        )
        return
      end
      first = row.first_attempted_at || now
      dead = attempts >= MAX_ATTEMPTS || first <= now - MAX_AGE
      backoff = [(2**attempts).minutes, MAX_BACKOFF].min
      updated = AgentPendingSync.where(id: row.id, generation: gen, dead_at: nil).update_all(
        attempts: attempts,
        first_attempted_at: first,
        last_attempt_at: now,
        last_error: error.to_s.truncate(2000),
        next_attempt_at: now + backoff,
        dead_at: dead ? now : nil,
        updated_at: now
      )
      report_dead!(row, attempts, error) if dead && updated.positive?
    end

    def report_dead!(row, attempts, error)
      subject = (row.kind == "firewall") ? "node #{row.node_id}" : "project #{row.project_id}"
      subject += " (#{row.key})" if row.key.present?
      SystemEvent.create!(
        message: "cs-agent sync gave up: #{row.kind} for #{subject} [region #{row.region_id}]",
        log_level: "warn",
        data: {
          "region_id" => row.region_id,
          "project_id" => row.project_id,
          "node_id" => row.node_id,
          "kind" => row.kind,
          "key" => row.key,
          "attempts" => attempts,
          "last_error" => error.to_s,
          "detail" => "Retry from the availability zone page (Retry dead) once the cause is fixed."
        },
        event_code: "9d2c4e71b0a8f365"
      )
    end

    # A live row older than STALE_AFTER since its drop was recorded (first_failed_at, so
    # rows stuck only on transport failures, which never count an attempt, still alert):
    # one SystemEvent per region per STALE_ALERT_WINDOW, with the kinds and counts.
    # Only reached when the region has a node to replay through.
    def report_stale!(region)
      counts = AgentPendingSync.where(region_id: region.id, dead_at: nil)
        .where(first_failed_at: ..STALE_AFTER.ago).group(:kind).count
      return if counts.empty?
      msg = "cs-agent syncs pending for over #{STALE_AFTER.inspect} in #{region.name} [region #{region.id}]"
      return if SystemEvent.where("message = ? AND created_at > ?", msg, STALE_ALERT_WINDOW.ago).exists?
      SystemEvent.create!(
        message: msg,
        log_level: "warn",
        data: {"region_id" => region.id, "kinds" => counts},
        event_code: "5a0e8f3c2b7d6194"
      )
    end

    # Never blocks: a pass already running for the region wins.
    def with_lock(region_id)
      conn = ActiveRecord::Base.connection
      return unless conn.select_value("SELECT pg_try_advisory_lock(#{ADVISORY_LOCK_CLASS}, #{region_id.to_i})")
      begin
        yield
      ensure
        conn.execute("SELECT pg_advisory_unlock(#{ADVISORY_LOCK_CLASS}, #{region_id.to_i})")
      end
    end
  end
end
