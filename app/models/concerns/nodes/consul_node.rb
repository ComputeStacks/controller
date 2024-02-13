module Nodes
  module ConsulNode
    extend ActiveSupport::Concern

    # @param [Boolean] trigger_reload whether or not to actually load the rules, or just update the db.
    # @return [Boolean]
    def update_iptable_config!(trigger_reload = true)
      data = consul_iptable_rules
      if Feature.check('log_iptables')
        SystemEvent.create!(
          message: "Log: Node IPTables",
          log_level: "debug",
          data: data,
          event_code: '14daeeb2d815f4b2'
        )
      end
      if Diplomat::Kv.put("nodes/#{hostname}/ingress_rules", data.to_json, consul_config)
        return trigger_reload ? trigger_consul_reload! : true
      end
      false
    end

    def consul_config
      return {} unless online?
      dc = region.name.strip.downcase
      {
        http_addr: "#{CONSUL_API_PROTO}://#{primary_ip}:#{CONSUL_API_PORT}",
        dc: dc.blank? ? nil : dc,
        token: region.consul_token
      }
    end

    private

    def consul_iptable_rules
      data = { rules: [] }
      iptable_rules.each do |i|
        if i.sftp_container # should never hit this...
          data[:rules] << {
            proto: i.proto,
            nat: i.port_nat,
            port: i.port,
            dest: i.sftp_container.local_ip,
            driver: i.network.nil? ? 'none' : i.network.network_driver
          }
        elsif i.container_service
          i.container_service.containers.each do |container|
            data[:rules] << {
              proto: i.proto,
              nat: i.port_nat,
              port: i.port,
              dest: container.local_ip,
              driver: i.network.nil? ? 'none' : i.network.network_driver
            }
          end
        end
      end
      data
    rescue => e
      ExceptionAlertService.new(e, 'ea45d8edfbcc4c7b').perform
      { rules: [] }
    end

    # @return [Boolean]
    def trigger_consul_reload!
      Diplomat::Kv.put("jobs/#{SecureRandom.uuid}", { name: "firewall", node: hostname }.to_json, consul_config)
    rescue => e
      ExceptionAlertService.new(e, 'd65f67fdfc21d33f').perform
      false
    end

  end
end
