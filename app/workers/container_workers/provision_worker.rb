module ContainerWorkers
  class ProvisionWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    ##
    # Seconds to wait before each network repair retry; its length is the retry limit.
    NETWORK_RETRY_BACKOFF = [30, 60, 120].freeze

    # args[0] = container_id GLOBALID
    # args[1] = event_id GLOBALID
    # args[2] = requested_state == default is 'running'
    # args[3] = network repair attempt, default 0. Only this worker sets it.
    def perform(*args)
      container = GlobalID::Locator.locate args[0]
      event = GlobalID::Locator.locate args[1]
      requested_state = args[2].nil? ? "running" : args[2]
      attempt = args[3].to_i

      return if container.nil? || event.nil?

      return unless event.start!

      return unless container.can_build? event
      return if Rails.env.test?

      # Ensure prerequisites are met
      return unless network_ready?(container, event, args, requested_state, attempt)
      return unless ProvisionServices::ImageReadyService.new(container, event).perform

      build_result = Timeout.timeout(70) do
        container.build! event
      end

      unless build_result
        event.fail! "Failed to build container"
        return
      end

      if requested_state == "stopped"
        event.event_details.create!(
          data: "Requested state was stop, so we are not starting this service.",
          event_code: "ee3be79e03dd3994"
        )
        event.done!
        return
      end

      ContainerWorkers::StartWorker.perform_async container.to_global_id.to_s, event.to_global_id.to_s
    rescue ActiveRecord::RecordNotFound
      nil # Silently fail
    rescue Timeout::Error
      if defined?(event) && event
        event.event_details.create!(
          data: "Failed to connect to container host: Connection Timeout.",
          event_code: "91868506d445e1f2"
        )
        event.fail! "Fatal error"
      end
    rescue Docker::Error::TimeoutError, Excon::Error::Socket, DockerSSH::ConnectionFailed => docker_timeout
      if defined?(event) && event
        if event.event_details.where(event_code: "b4123e9e96f04555").count > 2
          event.event_details.create!(
            data: "Max connection attempts hit, halting.",
            event_code: "b4123e9e96f04555"
          )
          event.fail! "Timeout"
        else
          event.event_details.create!(
            data: "Timeout hit, retrying...",
            event_code: "b4123e9e96f04555"
          )
          ContainerWorkers::ProvisionWorker.perform_in 1.minute, args[0], args[1], args[2], args[3]
          return
        end
      end
      ExceptionAlertService.new(docker_timeout, "b4123e9e96f04555").perform
    rescue => e
      user = nil
      if defined?(event) && event
        user = event.audit&.user
        event.event_details.create!(
          data: "Fatal Error\n#{e.message}",
          event_code: "e6367c8012b4ae28"
        )
        event.fail! "Fatal error"
      end
      ExceptionAlertService.new(e, "e6367c8012b4ae28", user).perform
    end

    private

    ##
    # Make sure the container has its project network and a private IP before building --
    # without them `build!` gets no runtime config and fails with nothing to say why.
    #
    # Retries by re-enqueueing this worker with a backoff rather than sleeping in it, then
    # fails the event with the reason.
    #
    # Containers in one order usually share the order's event (PowerCycleContainerService
    # reuses the audit's first event), so a final `fail!` here also stops any sibling's
    # pending retry at `event.start!`. Known and accepted.
    #
    # @return [Boolean] true when the build can go ahead
    def network_ready?(container, event, args, requested_state, attempt)
      service = NetworkServices::EnsureContainerNetworkService.new(container, event)
      result = service.perform
      return true if result == :ready

      if result == :retry && attempt < NETWORK_RETRY_BACKOFF.length
        backoff = NETWORK_RETRY_BACKOFF[attempt]
        event.event_details.create!(
          data: "Container #{container.name} is missing its network/IP: #{service.reason} Retrying in #{backoff}s (attempt #{attempt + 1}/#{NETWORK_RETRY_BACKOFF.length}).",
          event_code: "17bbda63e54e771f"
        )
        ContainerWorkers::ProvisionWorker.perform_in backoff, args[0], args[1], requested_state, attempt + 1
      else
        event.event_details.create!(
          data: "Unable to build container #{container.name}, it is missing its network/IP: #{service.reason}",
          event_code: "61b85fcbf2edef40"
        )
        event.fail! "Missing network"
      end
      false
    end
  end
end
