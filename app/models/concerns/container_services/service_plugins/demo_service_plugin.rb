module ContainerServices
  module ServicePlugins
    # Example plugin integration used for testing purposes.
    module DemoServicePlugin
      extend ActiveSupport::Concern

      included do
        scope :demo, -> { where("container_image_plugins.name = 'demo'").joins(:container_image_plugin) }
      end

      def demo_available?
        active && container_image_plugin.name == 'demo'
      end

      def demo_config(c = {})
        return c unless demo_available?
        c['Env'] << "CS_DEMO_PLUGIN=true"
        c
      end

    end
  end
end
