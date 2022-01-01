module ContainerServices

  ##
  # Manage Calico Policy for this service
  #
  module CalicoServicePolicy
    extend ActiveSupport::Concern

    def calico_policy
      lb_ip_list = calico_lb_ip_list
      tcp_ip_ports = ingress_rules.where("tcp_lb = false AND external_access = true AND port_nat > 0 AND proto = 'tcp'").pluck(:port)
      udp_ports = ingress_rules.where("external_access = 't' AND proto = 'udp' AND port_nat > 0").pluck(:port)
      tcp_lb_ports = ingress_rules.where(
        "external_access = true AND (proto = 'http' OR (tcp_lb = true AND proto != 'udp' AND port_nat > 0))"
      ).pluck(:port)

      policy = {
        apiVersion: 'v1',
        kind: 'policy',
        metadata: {
          name: name
        },
        spec: {
          order: 10,
          selector: %Q(service == "#{name}"),
          ingress: []
        }
      }
      policy[:spec][:ingress] << {
        action: 'allow',
        protocol: 'tcp',
        destination: {
          ports: tcp_lb_ports
        },
        source: {
          nets: lb_ip_list
        }
      } unless tcp_lb_ports.empty? || lb_ip_list.empty?
      policy[:spec][:ingress] << {
        action: 'allow',
        protocol: 'tcp',
        destination: {
          ports: tcp_ip_ports
        },
        source: {
          nets: ["0.0.0.0/0"]
        }
      } unless tcp_ip_ports.empty?
      policy[:spec][:ingress] << {
        action: 'allow',
        protocol: 'udp',
        destination: {
          ports: udp_ports
        },
        source: {
          nets: ["0.0.0.0/0"]
        }
      } unless udp_ports.empty?
      policy
    end

    private

    def calico_lb_ip_list
      return [] if load_balancer.nil?
      return [] unless ingress_rules.where(external_access: true).exists?
      ips = [load_balancer.public_ip]
      load_balancer.internal_ip.each do |i|
        ips << i unless ips.include?(i)
      end
      load_balancer.ext_ip.each do |i|
        ips << i unless ips.include?(i)
      end
      ips
    end

  end

end
