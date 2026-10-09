##
# Store Project Metadata
module ProjectServices
  class StoreMetadata
    attr_accessor :deployment

    def initialize(deployment)
      self.deployment = deployment
    end

    # @param record_drop [Boolean] false on replay (AgentWorkers::PendingSyncWorker), which
    #   does its own pending-sync bookkeeping
    # @param self_heal [Boolean] false on replay: never provision the tenant inline
    def perform(record_drop: true, self_heal: true)
      region = deployment&.region
      return false if region.nil?
      # Never push for a project being trashed: the self-heal would recreate its tenant.
      return false if Agent::TenantRegistry.deleting?(deployment.id)
      # Push the full overview (unchanged — we keep all data) to the node agent's
      # managed area instead of Consul KV. put_managed self-heals an unprovisioned
      # tenant. NotReady (no online node / no agent token) degrades to false,
      # matching the prior region-nil guard. A drop is recorded for replay.
      Agent::PendingSync.track(record_drop:, region:, project: deployment, kind: "managed_metadata") do
        Agent::Client.new(deployment, region: region).put_managed("metadata", overview.to_json, self_heal:)
      end
    rescue Agent::Client::NotReady
      false
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
        containers = i.containers.map do |c|
          {id: c.id, name: c.name, ip: c.ip_address&.ipaddr, node_id: c.node&.id}
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
            category: i.container_image.category,
            tags: i.container_image.tags,
            registry: i.image_variant&.full_image_path
          },
          containers:,
          ingress_rules:,
          package: package_data,
          settings:
        }
      end
      s
    end
  end
end
