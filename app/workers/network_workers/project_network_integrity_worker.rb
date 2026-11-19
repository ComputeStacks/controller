module NetworkWorkers
  ##
  # Report projects and containers that are missing their private network or IP address.
  #
  # ALERT ONLY: this never repairs anything. Builds repair themselves
  # (NetworkServices::EnsureContainerNetworkService); this sweep exists so that what slips past
  # them -- like the containers left with no network by the 2026-10-20 allocation race, which
  # nobody noticed until a rebuild failed -- is seen by an operator.
  #
  # One SystemEvent per kind of finding, updated in place on every run that still finds it
  # (latest findings, a run counter, last seen) rather than a new row every 30 minutes.
  # Nothing is written when everything is clean. Anything created or bound in the last
  # 15 minutes is ignored, so in-flight orders are not reported.
  class ProjectNetworkIntegrityWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    # Projects with active containers in a bridged region and no private network row.
    MISSING_NETWORK_EVENT_CODE = "3cfcb0d31d643ca1"

    # A project's private network row is bound but was never created (inactive).
    INACTIVE_NETWORK_EVENT_CODE = "be425927598a3590"

    # Active containers or SFTP containers with no private IP address.
    MISSING_IP_EVENT_CODE = "570daba83a500333"

    # Unexpected error (reported to the exception tracker).
    ERROR_EVENT_CODE = "9af82099e399db8b"

    # Grace period for in-flight orders.
    GRACE = 15.minutes

    # How many findings to list on the SystemEvent; the total is always recorded.
    MAX_LISTED = 100

    def perform
      cutoff = GRACE.ago
      check { projects_without_network(cutoff) }
      check { inactive_project_networks(cutoff) }
      check { containers_without_ip(cutoff) }
    end

    private

    # Each check runs on its own, so one that raises does not hide the others.
    def check
      yield
    rescue => e
      ExceptionAlertService.new(e, ERROR_EVENT_CODE).perform
    end

    # (a) Bridged regions only; clustered regions have no per-project network.
    def projects_without_network(cutoff)
      bridged = bridged_region_ids
      container_projects = Deployment::ContainerService
        .where(region_id: bridged)
        .where(id: Deployment::Container.active.where(created_at: ...cutoff).select(:container_service_id))
        .select(:deployment_id)
      sftp_projects = Deployment::Sftp.active
        .where(created_at: ...cutoff)
        .where(node_id: Node.where(region_id: bridged).select(:id))
        .select(:deployment_id)

      projects = Deployment
        .where(id: container_projects).or(Deployment.where(id: sftp_projects))
        .where.not(id: Network.where.not(deployment_id: nil).select(:deployment_id))
        .order(:id)

      report(
        MISSING_NETWORK_EVENT_CODE,
        projects.count,
        "project(s) with active containers have no private network",
        projects.limit(MAX_LISTED).pluck(:id, :name).map { |id, name| "Project #{name} (#{id})" }
      )
    end

    # (b) `updated_at` stands in for when the row was bound: pool rows are created long
    # before any project claims them.
    def inactive_project_networks(cutoff)
      networks = Network
        .where.not(deployment_id: nil)
        .where(active: false, region_id: bridged_region_ids)
        .where(updated_at: ...cutoff)
        .order(:id)

      report(
        INACTIVE_NETWORK_EVENT_CODE,
        networks.count,
        "project private network(s) are allocated but not active on the node",
        networks.limit(MAX_LISTED).pluck(:id, :name, :deployment_id).map { |id, name, project_id|
          "Network #{name} (#{id}) for project #{project_id}"
        }
      )
    end

    # (c) All regions, clustered included.
    def containers_without_ip(cutoff)
      containers = Deployment::Container.active.where.missing(:ip_address).where(created_at: ...cutoff)
      sftps = Deployment::Sftp.active.where.missing(:ip_address).where(created_at: ...cutoff)

      total = containers.count + sftps.count
      listed = containers.order(:id).limit(MAX_LISTED).pluck(:id, :name).map { |id, name| "Container #{name} (#{id})" }
      if listed.length < MAX_LISTED
        listed += sftps.order(:id).limit(MAX_LISTED - listed.length).pluck(:id, :name).map { |id, name| "SFTP container #{name} (#{id})" }
      end

      report(MISSING_IP_EVENT_CODE, total, "active container(s) have no private IP address", listed)
    end

    def bridged_region_ids
      Region.where.not(network_driver: "calico_docker").select(:id)
    end

    ##
    # Find-or-create the one SystemEvent for this code and record the latest findings on it.
    # Nothing at all when there are no findings.
    def report(event_code, total, summary, items)
      return if total.zero?

      message = "Network integrity: #{total} #{summary}"
      se = SystemEvent.find_by(event_code: event_code)
      if se.nil?
        se = SystemEvent.create!(
          message: message,
          log_level: "warn",
          data: {count: 0, first_seen: Time.now.utc},
          event_code: event_code
        )
      end
      previous = se.data.is_a?(Hash) ? se.data : {}
      se.update!(
        message: message,
        data: previous.merge(
          count: previous[:count].to_i + 1,
          total: total,
          items: items,
          last_seen: Time.now.utc
        )
      )
    end
  end
end
