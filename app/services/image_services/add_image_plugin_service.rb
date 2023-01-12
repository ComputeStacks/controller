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
                  :errors

    # @param [ContainerImage] image
    # @param [ContainerImagePlugin] plugin
    def initialize(image, plugin)
      self.image = image
      self.plugin = plugin
      self.cascade = false
      self.errors = []
    end

    # @return [Boolean]
    def perform
      if image << plugin
        cascade_plugin! if cascade
      else
        self.errors << image.errors.full_messages.join(", ")
      end
      errors.empty?
    end

    private

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

        p = s.service_plugins.new(
          container_image_plugin: plugin,
          active: plugin.active,
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
      s = service.subscription.subscription_products.new(
        product: plugin.product,
        allow_nil_phase: true
      )
      return true if s.save
      self.errors << "Error saving subscription product for service : #{service.id} | #{s.errors.full_messages.join(", ")}"
      false
    end

  end
end
