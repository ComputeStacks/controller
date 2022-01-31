##
# Store Project Metadata
module ProjectServices
  class StoreMetadata

    attr_accessor :deployment

    def initialize(deployment)
      self.deployment = deployment
      @consul_base = "projects/#{deployment.token}"
    end

    def perform
      return false if deployment.region.consul_config.nil?
      Diplomat::Kv.put("#{@consul_base}/metadata", overview.to_json, deployment.region.consul_config)
    end

    def overview
      {
        project: {
          id: deployment.id,
          name: deployment.name
        },
        services: overview_services
      }
    end

    def overview_services
      s = []
      deployment.services.each do |i|
        containers = i.containers.map  do |c|
          { id: c.id, name: c.name, ip: c.ip_address&.ipaddr }
        end
        ingress_rules = i.ingress_rules.map do |c|
          {
            proto: c.proto,
            port: c.port,
            external_access: c.external_access,
            backend_ssl: c.backend_ssl,
            tcp_proxy_opt: c.tcp_proxy_opt,
            nat: c.port_nat.zero? ? nil : c.port_nat
          }
        end
        settings = i.setting_params.map do |c|
          {
            name: c.name,
            label: c.label,
            param_type: c.param_type,
            decrypted_value: c.decrypted_value
          }
        end
        package_data = if i.package
                         {
                           label: i.package.product.label,
                           cpu: i.package.cpu,
                           memory: i.package.memory,
                           storage: i.package.storage,
                           bandwidth: i.package.bandwidth,
                           local_disk: i.package.local_disk,
                           memory_swap: i.package.memory_swap,
                           memory_swappiness: i.package.memory_swappiness
                         }
                       else
                         {}
                       end
        s << {
          id: i.id,
          name: i.name,
          label: i.label,
          created_at: i.created_at,
          domains: i.domains.pluck(:domain),
          image: {
            id: i.container_image.id,
            label: i.container_image.label,
            role: i.container_image.role,
            category: i.container_image.role_class,
            tags: i.container_image.tags
          },
          containers: containers,
          ingress_rules: ingress_rules,
          package: package_data,
          settings: settings
        }
      end
      s
    end


  end
end
