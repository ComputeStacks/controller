module Nodes
  # NB: the concern keeps its historical name Nodes::ConsulNode (cosmetic) to limit the blast
  # radius of the Consul retirement — firewall rules now flow to the node's cs-agent over HTTP
  # (Agent::Client#put_firewall_rules), not Consul KV. The agent reconciles nftables on the PUT
  # (there is no separate reload trigger).
  module ConsulNode
    extend ActiveSupport::Concern

    # Push this node's firewall (NAT) rules to its cs-agent. The agent reconciles nftables on
    # the PUT — there is no reload step.
    # @return [Boolean]
    def update_iptable_config!
      data = consul_iptable_rules
      # A rule-build failure yields nil, never an empty ruleset. The agent reconciles nftables
      # to exactly what it receives, so PUTting {rules: []} would close every published port on
      # this node — a dark outage from a transient error (e.g. a nil network mid-migration).
      # Report "not pushed" instead; callers already treat false that way, and the cutover
      # backfill leaves the node un-latched so a re-run retries it.
      return false if data.nil?

      if Feature.check("log_iptables")
        SystemEvent.create!(
          message: "Log: Node IPTables",
          log_level: "debug",
          data: data,
          event_code: "14daeeb2d815f4b2"
        )
      end
      pushed = Agent::Client.for_node(self).put_firewall_rules(hostname, data)
      report_firewall_push_failure! unless pushed
      pushed
    end

    private

    # A failed push leaves this node's nftables stale, and until now that was invisible:
    # put_firewall_rules folds transport errors into `false` (so ReloadIptableWorker's own
    # rescues never fire, and it discards the return value anyway), while a non-2xx from the
    # agent returns false with no report at all. Nothing re-pushes on a schedule — the only
    # triggers are ingress-rule changes and network migration — so a silent failure persists
    # until an unrelated change happens to retry it. Reported here rather than in the worker
    # so every caller is covered. Deduped like Agent::Client#report_changelog_error.
    def report_firewall_push_failure!
      # Node id in the message, not only in the data: labels carry no uniqueness constraint,
      # and the dedupe below matches on the message — two nodes sharing a label would suppress
      # each other's events forever, hiding the second node's stale rules entirely.
      msg = "cs-agent firewall push failed on #{label} [node #{id}]"
      return if SystemEvent.where("message = ? AND created_at > ?", msg, 15.minutes.ago).exists?

      SystemEvent.create!(
        message: msg,
        log_level: "warn",
        data: {
          "node_id" => id,
          "agent_address" => agent_address,
          "detail" => "Agent did not accept the firewall push. NAT rules on this node are now stale; re-run Node#update_iptable_config! once it is reachable."
        },
        event_code: "6b0f2d4c9a71e835"
      )
    end

    def consul_iptable_rules
      data = {rules: []}
      iptable_rules.each do |i|
        if i.sftp_container # should never hit this...
          data[:rules] << {
            proto: i.proto,
            nat: i.port_nat,
            port: i.port,
            dest: i.sftp_container.local_ip,
            driver: i.network.nil? ? "none" : i.network.network_driver
          }
        elsif i.container_service
          i.container_service.containers.each do |container|
            data[:rules] << {
              proto: i.proto,
              nat: i.port_nat,
              port: i.port,
              dest: container.local_ip,
              driver: i.network.nil? ? "none" : i.network.network_driver
            }
          end
        end
      end
      data
    rescue => e
      ExceptionAlertService.new(e, "ea45d8edfbcc4c7b").perform
      nil
    end
  end
end
