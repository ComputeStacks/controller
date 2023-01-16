module ProvisionServices
  class ImageReadyService

    attr_accessor :container,
                  :event

    def initialize(container, event)
      self.container = container
      self.event = event
    end

    def perform
      if container.is_a?(Deployment::Container)

        # Ensure container image exists and is updated (for custom images)
        if container.image_variant.pull_image?(container.node)
          image_service = NodeServices::PullImageService.new(container.node, container.image_variant)
          unless image_service.perform
            event.event_details.create!(
              data: image_service.errors.empty? ? "Failed to pull image" : "Error pulling image:\n\n#{image_service.errors.join("\n")}",
              event_code: 'c3e71c83bc061e34'
            )
            event.fail! 'Failed to pull image'
            # Also revalidate the image...
            ImageWorkers::ValidateTagWorker.perform_async(container.image_variant.global_id)
            return false
          end
        end

        # Ensure container links are met
        unless container.service.init_link!
          event.event_details.create!(
            data: 'Missing dependent containers',
            event_code: '9c248764c6609225'
          )
          event.fail! 'Missing dependencies'
          return false
        end

      else

        # Ensure container image exists
        unless container.image_exists?
          event.event_details.create!(
            data: 'Failed to pull image',
            event_code: 'c480f573e5347028'
          )
          event.fail! 'Image not available'
          return false
        end

      end
      true
    rescue => e
      user = nil
      if defined?(event) && event
        user = event.audit&.user
        event.event_details.create!(
          data: "Fatal Error\n#{e.message}",
          event_code: '07501fdbfa48297f'
        )
        event.fail! 'Fatal error'
      end
      ExceptionAlertService.new(e, '00d225d8343f7385', user).perform
      false
    end

  end
end
