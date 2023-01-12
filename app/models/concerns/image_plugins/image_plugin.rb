module ImagePlugins
  module ImagePlugin
    extend ActiveSupport::Concern

    included do
      has_and_belongs_to_many :container_image_plugins

      attr_accessor :add_plugin_id
      validate :valid_plugin?
      before_save :add_plugin_by_id
    end

    private

    def valid_plugin?
      return if add_plugin_id.blank?
      if current_user.nil?
        errors.add(:base, "Missing user, unable to add plugin")
        return
      end
      p = ContainerImagePlugin.find_by id: add_plugin_id
      if p.nil?
        errors.add(:base, "Unknown plugin")
        return
      end
      unless p.active
        errors.add(:base, "Invalid Plugin")
        return
      end
      unless p.can_enable?(current_user)
        errors.add(:base, "Permission Denied")
      end
    end

    def add_plugin_by_id
      return if add_plugin_id.blank?
      if current_user.nil?
        errors.add(:base, 'missing user who performed this action')
        return
      end
      plugin = ContainerImagePlugin.find_by id: add_plugin_id
      if plugin.nil?
        errors.add(:base, "unknown plugin #{add_plugin_id}")
        return
      end
      unless plugin.active
        errors.add(:base, "plugin unavailable")
        return
      end
      unless plugin.can_enable?(current_user)
        errors.add(:base, "permission denied")
        return
      end
      return if container_image_plugins.exists?(plugin.id)

      container_image_plugins << plugin
    end

  end
end
