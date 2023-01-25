module ContainerServices
  module ServicePlugins
    extend ActiveSupport::Concern

    included do

      has_many :service_plugins,
               class_name: "Deployment::ContainerService::ServicePlugin",
               foreign_key: 'deployment_container_service_id',
               dependent: :destroy

      has_many :container_image_plugins, through: :service_plugins

      attr_accessor :new_plugin_list
      after_update :update_plugin_list, if: Proc.new { new_plugin_list }
    end

    # Return a pristine list of plugins a user can enable
    # @return [Array]
    def available_plugins
      service_plugins.optional.to_a.delete_if do |i|
        !i.user_selectable?
      end
    end

    # Helper method to determine If we show the monarx button
    # This should be replaced with something that works for all plugins
    def monarx_available?
      return false if service_plugins.active.monarx.empty?
      service_plugins.active.monarx.first.monarx_available?
    end

    private

    def update_plugin_list
      change_list = []
      service_plugins.optional.each do |i|
        if new_plugin_list.include?(i.id) && !i.active
          change_list << "Addon '#{i.label}' moved from inactive to active."
          i.current_audit = current_audit if current_audit
          i.update active: true
        elsif !new_plugin_list.include?(i.id) && i.active
          change_list << "Addon '#{i.label}' moved from active to inactive."
          i.current_audit = current_audit if current_audit
          i.update active: false
        end
      end
      return if change_list.empty?
      return if current_audit.nil?
      e = event_logs.create!(
        locale: 'service.addons',
        locale_keys: {
          label: name
        },
        status: 'completed',
        audit: current_audit,
        event_code: '1245f430e0f54052'
      )
      e.deployments << deployment
      e.event_details.create!(
        data: change_list.join("\n"),
        event_code: '1245f430e0f54052'
      )
    end

  end
end
