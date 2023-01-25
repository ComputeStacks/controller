module ImagePlugins
  module Marketplace
    module Demo
      extend ActiveSupport::Concern

      # @param [Deployment::ContainerService::ServicePlugin] service_plugin
      def marketplace_usage_for_demo(service_plugin)
        {
          table: "v1.plugin_demo",
          fields: %w(service qty),
          values: [
            service_plugin.container_service.name,
            service_plugin.container_service.containers.count
          ]
        }
      end

    end
  end
end
