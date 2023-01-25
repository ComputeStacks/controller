module ImageServices
  ##
  # Remove a plugin from an image, and cascade the removal to all services.
  class RemoveImagePluginService

    attr_accessor :image,
                  :plugin,
                  :current_user,
                  :errors

    # @param [ContainerImage] image
    # @param [ContainerImagePlugin] plugin
    def initialize(image, plugin)
      self.image = image
      self.plugin = plugin
      self.errors = []
      self.current_user = nil
    end

    # @return [Boolean]
    def perform
      return false unless valid?

      # First step, remove plugin from services
      return false unless cascade_removal!

      # If that was successful, then remove the plugin from the image
      unless image.container_image_plugins.delete plugin
        errors << "Error removing plugin: #{image.errors.full_messages.join(', ')}"
      end

      errors.empty?
    end

    private

    # Do we have everything to perform this?
    # @return [Boolean]
    def valid?
      if current_user.is_a?(User)
        errors << "Unauthorized" unless current_user.is_admin
      else
        errors << "Missing performed by user"
      end
      errors.empty?
    end

    # Cascade removal through all linked services
    # @return [Boolean]
    def cascade_removal!
      plugin.service_plugins.each do |sp|
        sp.current_user = current_user
        # First set to inactive to update subscriptions
        if sp.update active: false
          unless sp.destroy # If successfully deactivated, remove it completely
            errors << "Error removing service plugin #{sp.id}: #{sp.errors.join(', ')}"
          end
        else
          errors << "Error updating service plugin #{sp.id}: #{sp.errors.join(', ')}"
          next
        end

      end
      errors.empty?
    end

  end
end
