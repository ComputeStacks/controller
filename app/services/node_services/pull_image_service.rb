module NodeServices
  class PullImageService

    attr_accessor :node,
                  :container_image,
                  :image_variant,
                  :errors,
                  :raw_image # Useful for pulling system images

    def initialize(node, image_variant = nil)
      self.node = node
      self.image_variant = image_variant
      self.container_image = image_variant&.container_image
      self.raw_image = nil
      self.errors = []
    end

    # @return [Boolean]
    def perform
      return false unless valid?
      result = Timeout::timeout(90) do
        Docker::Image.create({'fromImage' => image_path}, image_auth, node.client(5))
      end
      result.is_a? Docker::Image
    rescue Timeout::Error
      errors << "Failed to pull container image: Connection Timeout."
      false
    rescue Docker::Error::NotFoundError => e
      SystemEvent.create!(
        message: "ContainerImage Error: NotFoundError",
        log_level: 'warn',
        data: {
          'image' => {
            'id' => container_image&.id,
            'name' => container_image&.name
          },
          'error' => e.message
        },
        event_code: 'f20fa0bfb26e6397'
      )
      errors << e.message
      false
    rescue Docker::Error::ServerError => e
      SystemEvent.create!(
        message: "Registry Error: Unable to connect",
        log_level: 'warn',
        data: {
          'message' => 'We were unable to connect to the container registry to pull this image. It could be temporary, or indicates an issue with the registry provider.',
          'image' => {
            'id' => container_image&.id,
            'name' => container_image&.name
          },
          'error' => e.message
        },
        event_code: '1fca3e3e13408e13'
      )
      errors << e.message
      false
    rescue => e
      ExceptionAlertService.new(e, 'd88036886500af68').perform unless e.message =~ /auth/
      SystemEvent.create!(
        message: "ContainerImage Error: Fatal",
        log_level: 'warn',
        data: {
          'image' => {
            'id' => container_image&.id,
            'name' => container_image&.name
          },
          'error' => e.message
        },
        event_code: '811590dcbd5da281'
      )
      errors << e.message
      false
    end

    private

    # @return [Boolean]
    def valid?
      return false if node.nil?
      return false unless node.online?
      return false if container_image.nil? && raw_image.nil?
      return true if container_image.nil?

      if !image_variant.validated_tag && image_variant.exists_on_node?(node)
        # Even if our validation failed, allow it to proceed if it exists on node.
        return true
      elsif !image_variant.validated_tag
        return false
      end

      true
    end

    def image_path
      image_variant.nil? ? raw_image : image_variant.full_image_path
    end

    def image_auth
      container_image.nil? ? nil : container_image.image_auth
    end

  end
end
