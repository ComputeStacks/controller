module Projects
  module CalicoProjectPolicy
    extend ActiveSupport::Concern

    def calico_policy
      {
        apiVersion: 'v1',
        kind: 'policy',
        metadata: {
          name: token
        },
        spec: {
          order: 1,
          selector: %Q(token == "#{token}"),
          ingress: [
            {
              action: 'allow',
              source: {
                selector: %Q(token == "#{token}")
              }
            }
          ],
          egress: calico_egress_rules,
        }
      }
    end

    private

    # @return [Array]
    def calico_egress_rules
      rules = [{
        action: 'allow',
        protocol: 'tcp',
        source: {
          selector: %Q(token == "#{token}")
        },
        destination: {
          nets: calico_node_ips,
          ports: %w(80 443 8500 10000:59999)
        }
      }]
      rules << {
        action: 'deny',
        source: {
          selector: %Q(token == "#{token}")
        },
        destination: {
          nets: calico_nfs_hosts
        }
      } unless calico_nfs_hosts.empty?
      rules << {
        action: 'deny',
        source: {
          selector: %Q(token == "#{token}")
        },
        destination: {
          nets: calico_node_ips
        }
      }
      rules << {
        action: 'allow',
        source: {
          selector: %Q(token == "#{token}")
        },
        destination: {}
      }
      rules
    end

    ##
    # List all internal IPs.
    # @return [Array]
    # def calico_lb_internal
    #   ips = []
    #   LoadBalancer.all.each do |lb|
    #     lb.internal_ip.each do |ip|
    #       ips << ip unless ips.include? ip
    #     end
    #   end
    #   ips
    # end

    # @return [Array]
    def calico_nfs_hosts
      Region.where(Arel.sql( %q(nfs_remote_host is not null AND nfs_remote_host != '' AND nfs_remote_host != ' ') )).pluck(:nfs_remote_host)
    end

    # @return [Array]
    def calico_node_ips
      Node.where( Arel.sql( %q(primary_ip is not null and primary_ip != '' and primary_ip != ' ') ) ).pluck(:primary_ip)
    end

  end
end
