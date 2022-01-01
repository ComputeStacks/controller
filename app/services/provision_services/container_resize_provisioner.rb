module ProvisionServices
  ##
  # Resize a container given a billing package
  class ContainerResizeProvisioner
    attr_accessor :container,
                  :package,
                  :event

    # @!attribute [Deployment::Container] container
    # @!attribute [EventLog] event
    # @!attribute [BillingPackage] package
    def initialize(container, event, package)
      self.container = container
      self.package = package
      self.event = event
    end

    def perform
      return false unless event.active?
      return false unless update_container!
      container.update(
        cpu: package.cpu,
        memory: package.memory
      )
      container.subscription.new_package! package
    end

    private

    def update_container!
      mem_value = (package.memory * 1048576).to_i
      mem_swap = if package.memory_swap
                   mem_value + (package.memory_swap * 1048576).to_i
                 else
                   mem_value
                 end
      resources = {
        'NanoCPUs' => (package.cpu * 1e9).to_i,
        'Memory' => mem_value,
        'MemorySwap' => mem_swap
      }
      return true if Rails.env.test?
      client = container.docker_client
      if client.nil?
        event.event_details.create!(
          data: "Container does not exist on host",
          event_code: '00c74eadd4b2fab6'
        )
        event.fail! 'Container does not exist on host'
        return false
      end
      client.update resources
      true
    rescue => e
      # Catch and handle this event:
      #     Cannot update container 3287cc599c74c6102147b7bd5cb14fa01d1a07ba9cf789f316486a2d45a62892:
      #     docker-runc did not terminate sucessfully: failed to write 512000000 to memory.limit_in_bytes: write
      #     /sys/fs/cgroup/memory/docker/3287cc599c74c6102147b7bd5cb14fa01d1a07ba9cf789f316486a2d45a62892/memory.limit_in_bytes:
      #     device or resource busy
      if e.message =~ /docker-runc did not terminate/
        if event # Only proceed if there is an actual event
          if event.event_details.where(event_code: "c23cfb2ca12c6ded").exists?
            # We've tried once already, terminate this request.
            event.update(status: 'failed', state_reason: "Fatal Error", event_code: "c23cfb2ca12c6ded")
            event.event_details.create!(data: e.message, event_code: "c23cfb2ca12c6ded")
          elsif c.is_a?(Docker::Container) # Only proceed if we have a client.
            # Stop the container and try again
            event.update(status: 'pending', state_reason: "Container error, retrying.", event_code: "c23cfb2ca12c6ded")
            event.event_details.create!(data: e.message, event_code: "c23cfb2ca12c6ded")
            c.stop
            retry!
          else # Have an event, first time, but no client exists. Log the error and break out.
            event.update(status: 'failed', state_reason: "Fatal Error", event_code: "c23cfb2ca12c6ded")
            event.event_details.create!(data: e.message, event_code: "c23cfb2ca12c6ded")
          end
        else # Only alert us if there is no event to record the data.
          ExceptionAlertService.new(e, 'c23cfb2ca12c6ded').perform
        end
      else
        ExceptionAlertService.new(e, '05166515e7b2a4a2').perform
        if event
          event.update(status: 'failed', state_reason: "Fatal Error", event_code: "05166515e7b2a4a2")
          event.event_details.create!(data: e.message, event_code: "05166515e7b2a4a2")
        end
      end
      false
    end

    def retry!
      return if event.event_details.where(event_code: 'c23cfb2ca12c6ded').exists?
      sleep(2)
      perform
    end

  end
end
