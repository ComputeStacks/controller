module Nodes
  ##
  # The one place that turns a node's maintenance columns into something to show:
  # the admin API's `maintenance_status` object, the rollups on regions and
  # locations, and the wording the admin UI renders. It reads columns only and
  # never calls the agent, so it is safe to render for every node in a list.
  #
  #   Nodes::MaintenanceStatusPresenter.new(node).as_json
  #   Nodes::MaintenanceStatusPresenter.summary(region.nodes)
  #   Nodes::MaintenanceStatusPresenter.pending_agent_syncs([region.id])
  #
  # Where the data comes from:
  # * `maintenance_requested` / `_reason` / `_gen` -- the controller's request.
  # * `maintenance_holds` -- what the agent last reported (holds, sample,
  #   skipped backups), projected from the changelog or a direct GET.
  # * `maintenance_status` -- the drift worker's last GET: running work, pending
  #   count, quiesce, `observed_at`, and `mismatch_since`.
  class MaintenanceStatusPresenter
    # Any hold older than this is flagged; the drift worker alerts on the same age.
    STALE_HOLD_AFTER = 12.hours

    # Drift polls every 2 minutes; a few missed cycles means we are flying blind.
    STATUS_STALE_AFTER = 10.minutes

    WARNINGS = {
      "mismatch" => "Controller and node disagree about the controller hold",
      "stale_hold" => "Held for more than 12 hours",
      "unsupported_agent" => "Agent older than 3.4: maintenance is not enforced on the node",
      "status_stale" => "Agent status is stale",
      "override_pending" => "Override not yet delivered to the node"
    }.freeze

    attr_reader :node

    def initialize(node)
      @node = node
    end

    ##
    # The `maintenance_status` object for the admin API.
    def as_json(*)
      {
        "effective" => effective?,
        "requested" => node.maintenance_requested,
        "reason" => node.maintenance_reason,
        "requested_at" => node.maintenance_requested ? node.maintenance_updated : nil,
        "gen" => node.maintenance_gen,
        "holds" => {
          "controller" => node.maintenance_controller_hold,
          "local" => node.maintenance_local_hold
        },
        "paused_since" => parse_time(holds["paused_since"]),
        "skipped_backups" => skipped_backups,
        "sample" => sample,
        "agent" => {
          "supported" => node.agent_maintenance_supported?,
          "observed_at" => status["observed_at"],
          "instance_id" => node.agent_instance_id
        },
        "running" => running,
        "pending" => status["pending"],
        "warnings" => warnings
      }
    end

    ##
    # What a write to the controller hold returns over the API: the effective
    # value, the request, and the full status object.
    def write_response
      {
        "maintenance" => node.maintenance,
        "maintenance_requested" => node.maintenance_requested,
        "maintenance_gen" => node.maintenance_gen,
        "maintenance_status" => as_json
      }
    end

    def effective?
      node.maintenance ? true : false
    end

    def held_by
      node.maintenance_held_by
    end

    def since
      node.maintenance_since
    end

    # The agent's work sample while paused, or nil.
    def sample
      s = holds["sample"]
      s.is_a?(Hash) ? s : nil
    end

    def skipped_backups
      holds["skipped_backups"].to_i
    end

    # Running work from the drift worker's last GET.
    def running
      r = status["running"]
      r.is_a?(Array) ? r : []
    end

    # "quiesced" | "busy" | "unknown" | nil. The changelog sample is fresher than
    # the drift GET when both exist.
    def quiesce
      sample&.dig("quiesce").presence || status["quiesce"].presence
    end

    def quiesced?
      quiesce == "quiesced"
    end

    # Number of running tasks, from the sample when there is one.
    def running_count
      return sample["running_count"].to_i if sample&.key?("running_count")
      running.size
    end

    # When the quiesce figure was measured.
    def sampled_at
      parse_time(sample&.dig("sampled_at")) || observed_at
    end

    def observed_at
      parse_time(status["observed_at"])
    end

    def warnings
      list = []
      list << "mismatch" if status["mismatch_since"].present?
      list << "stale_hold" if stale_hold?
      list << "unsupported_agent" if unsupported_agent?
      list << "status_stale" if status_stale?
      list << "override_pending" if node.maintenance_override_gen.present?
      list
    end

    def warnings?
      warnings.any?
    end

    # [[code, label], ...]
    def warning_labels
      warnings.map { |code| [code, WARNINGS.fetch(code, code)] }
    end

    ##
    # "held by node (docker-upgrade), since 14:02 UTC", "held by controller and
    # node (kernel / docker-upgrade) ...". nil when not in maintenance.
    def held_by_text
      return nil unless effective?
      parts = held_by.map do |who|
        reason = (who == "controller") ? node.maintenance_reason : node.maintenance_local_hold&.dig("reason")
        reason.present? ? "#{who} (#{reason})" : who
      end
      text = parts.empty? ? "held" : "held by #{parts.join(" and ")}"
      at = format_time(since)
      at ? "#{text}, since #{at}" : text
    end

    ##
    # "Quiesced", "Quiescing: 2 running", or "Quiesce state unknown", with the
    # sample age. nil outside maintenance or with nothing reported yet.
    def quiesce_text
      return nil unless effective? && quiesce
      text = case quiesce
      when "quiesced" then "Quiesced"
      when "busy" then "Quiescing: #{running_count} running"
      else "Quiesce state unknown"
      end
      at = sampled_at
      at ? "#{text} (#{time_ago(at)})" : text
    end

    # "14:02 UTC" for a hold's `since` (unix seconds or ISO), or nil.
    def hold_since_text(hold)
      format_time(parse_time(hold&.dig("since")))
    end

    # One-line state for the node card's Status row.
    def state_text
      return nil unless effective?
      "In Maintenance (#{held_by.empty? ? "pending" : held_by.join(" + ")})"
    end

    class << self
      ##
      # The maintenance rollup for a set of nodes (a region's, or a location's).
      # One query; columns only.
      #
      # @param nodes [ActiveRecord::Relation<Node>, Array<Node>]
      # @param include_region [Boolean] add `region_id` to each listed node
      def summary(nodes, include_region: false)
        nodes = nodes.to_a
        held = nodes.select(&:maintenance)
        presenters = nodes.map { |n| new(n) }
        {
          "nodes_total" => nodes.size,
          "nodes_in_maintenance" => held.size,
          "nodes_quiesced" => presenters.count { |p| p.effective? && p.quiesced? },
          "nodes_with_warnings" => presenters.count(&:warnings?),
          "nodes" => held.sort_by { |n| n.label.to_s }.map do |n|
            item = {
              "id" => n.id,
              "label" => n.label,
              "held_by" => n.maintenance_held_by,
              "since" => n.maintenance_since
            }
            item["region_id"] = n.region_id if include_region
            item
          end
        }
      end

      ##
      # Agent writes waiting to be re-pushed (agent_pending_syncs), across the
      # given regions, in one query.
      #
      # @return [Hash] {"pending", "dead", "oldest_at"}
      def pending_agent_syncs(region_ids)
        pending, dead, oldest = AgentPendingSync.where(region_id: region_ids).pick(
          Arel.sql("COUNT(*) FILTER (WHERE dead_at IS NULL)"),
          Arel.sql("COUNT(*) FILTER (WHERE dead_at IS NOT NULL)"),
          Arel.sql("MIN(first_failed_at) FILTER (WHERE dead_at IS NULL)")
        )
        {"pending" => pending.to_i, "dead" => dead.to_i, "oldest_at" => oldest}
      end
    end

    private

    def holds
      @holds ||= node.maintenance_holds.is_a?(Hash) ? node.maintenance_holds : {}
    end

    def status
      @status ||= node.maintenance_status.is_a?(Hash) ? node.maintenance_status : {}
    end

    def stale_hold?
      return false unless effective?
      at = since
      at.present? && at < STALE_HOLD_AFTER.ago
    end

    # Only worth saying while the controller is asking for a hold the node
    # cannot enforce; before the fleet is on 3.4 it would otherwise be on every node.
    def unsupported_agent?
      return false unless node.maintenance_requested
      return true if node.agent_token.blank?
      at = node.agent_maintenance_unsupported_at
      return false if at.nil?
      seen = observed_at
      seen.nil? || seen < at
    end

    def status_stale?
      return false unless effective? && node.agent_maintenance_supported?
      seen = observed_at
      seen.nil? || seen < STATUS_STALE_AFTER.ago
    end

    # The agent sends unix seconds (Integer); stored state may also hold ISO strings.
    def parse_time(value)
      return nil if value.blank?
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return Time.at(value).utc if value.is_a?(Numeric)
      return Time.at(value.to_i).utc if value.to_s.match?(/\A\d+\z/)
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def format_time(time)
      return nil if time.nil?
      t = time.utc
      (t > 24.hours.ago) ? t.strftime("%H:%M UTC") : t.strftime("%b %-d %H:%M UTC")
    end

    def time_ago(time)
      ActionController::Base.helpers.time_ago_in_words(time)
    end
  end
end
