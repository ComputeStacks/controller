module ImagePlugins
  module Marketplace
    module Monarx
      extend ActiveSupport::Concern

      # @param [Deployment::ContainerService::ServicePlugin] service_plugin
      def marketplace_usage_for_monarx(service_plugin)
        return {} unless service_plugin.container_image_plugin.monarx_available?
        {
          table: "v1.plugin_monarx",
          fields: %w(service enterprise_id agent_id qty),
          values: [
            service_plugin.container_service.name,
            Setting.monarx_enterprise_id,
            service_plugin.monarx_agent_id,
            1
          ]
        }
      end

    end
  end
end
