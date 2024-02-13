module ImageServices
  ##
  # Add a plugin to an image
  #
  # @!attribute image
  #   @return [ContainerImage]
  # @!attribute plugin
  #   @return [ContainerImagePlugin]
  # @!attribute cascade
  #   When adding a plugin, should we also add that to all child services?
  #   @return [Boolean]
  # @!attribute errors
  #   @return [Array]
  #
  class AddImagePluginService

    attr_accessor :image,
                  :plugin,
                  :cascade,
                  :current_user,
                  :errors

    # @param [ContainerImage] image
    # @param [ContainerImagePlugin] plugin
    def initialize(image, plugin)
      self.image = image
      self.plugin = plugin
      self.cascade = false
      self.current_user = nil
      self.errors = []
    end

    # @return [Boolean]
    def perform
      return false unless valid?

      image.current_user = current_user
      if image.update add_plugin_id: plugin.id
        cascade_plugin! if cascade
      else
        self.errors << image.errors.full_messages.join(", ")
      end
      errors.empty?
    end

    private

    def valid?
      if current_user.is_a?(User)
        errors << "Unauthorized" unless current_user.is_admin
      else
        errors << "Missing performed by user"
      end
      unless plugin.is_a?(ContainerImagePlugin)
        errors << "Unknown plugin"
      end
      unless image.is_a?(ContainerImage)
        errors << "Unknown image"
      end
      errors.empty?
    end

    # @return [Boolean]
    def cascade_plugin!
      image.deployed_services.each do |s|
        # Create subscription, If:
        #   * has associated product
        #   * is active
        #   * is not optional
        if plugin.product && s.subscription
          if plugin.active && !plugin.is_optional
            next unless init_subscription!(s)
          end
        end

        # Plugin is active & optional? Initially set to inactive
        # Plugin is active & not optional? Initially set to active
        p = s.service_plugins.new(
          container_image_plugin: plugin,
          active: plugin.active && !plugin.is_optional,
          is_optional: plugin.is_optional
        )
        unless p.save
          self.errors << "Error creating plugin for service: #{s.id} | #{p.errors.full_messages.join(", ")}"
        end
      end
      errors.empty?
    end

    # @param [Deployment::ContainerService] service
    # @return [Boolean]
    def init_subscription!(service)
      subscription = service.subscription
      subscription.current_user = current_user
      sp = subscription.add_product! plugin.product
      return true if sp.errors.empty?

      self.errors << "Error saving subscription product for service : #{service.id} | #{sp.errors.full_messages.join(", ")}"
      false
    end

  end
end
