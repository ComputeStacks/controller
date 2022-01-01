module ContainerServices
  ##
  # Delete a container
  #
  # This should never be called directly.
  #
  # Called from:
  # * Delete service
  # * Horizontal Scale Down
  #
  # @!attribute container
  #   @return [Deployment::Container]
  # @!attribute event
  #   @return [EventLog]
  # @!attribute fail_counter
  #   @return [Integer]
  class TrashContainer

    attr_accessor :container,
                  :fail_counter,
                  :event

    def initialize(container, event)
      self.container = container # Could be either Container or Sftp
      self.event = event
      self.fail_counter = 0
    end

    # @return [Boolean]
    def perform
      container.set_inactive!
      if container.is_a?(Deployment::Sftp)
        container.update to_trash: true
        sftp_port_clean
      end
      trash_container
    rescue => e
      ExceptionAlertService.new(e, 'e2811a0537359044', event.audit&.user).perform
      event.event_details.create!(
        data: "Fatal error!\n\n#{e.message}",
        event_code: '83f412d78229f3a5'
      )
      false
    end

    private

    # @return [Boolean]
    def trash_container
      return false unless container.stop!(event, true)
      sleep(2)
      container.delete_from_node!(event)
      trash_local_container!
    rescue Docker::Error::TimeoutError => e
      if fail_counter < 3
        self.fail_counter += 1
        sleep(2)
        trash_container
      else
        event.event_details.create!(
          data: "Failed to destroy #{container.is_a?(Deployment::Container) ? 'container' : 'sftp container'} #{container.name}: #{e.message}",
          event_code: '3085231e621c2b16'
        )
        return false
      end
    rescue Docker::Error::NotFoundError => err
      ExceptionAlertService.new(err, '48247877795d5c7e', event.audit&.user).perform
      trash_local_container!
    end

    ##
    # Delete local db instance of container
    #
    # @return [Boolean]
    def trash_local_container!
      if container.destroy
        event.event_details.create!(
          data: "Successfully destroyed container: #{container.name}",
          event_code: '21cdb02746c1cdea'
        )
        true
      else
        event.event_details.create!(
          data: "Error deleting container: #{container.name}\n\n#{container.errors.full_messages.join(' ')}",
          event_code: 'e3046634f010d0ce'
        )
        false
      end
    end

    def sftp_port_clean
      container.ingress_rules.each do |i|
        i.toggle_nat! unless i.public_port.zero? # Ensure we free up the port
      end
    end

  end
end
