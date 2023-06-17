module ContainerWorkers
  class ProvisionWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # args[0] = container_id GLOBALID
    # args[1] = event_id GLOBALID
    # args[2] = requested_state == default is 'running'
    def perform(*args)
      container = GlobalID::Locator.locate args[0]
      event = GlobalID::Locator.locate args[1]
      requested_state = args[2].nil? ? 'running' : args[2]

      return if container.nil? || event.nil?

      return unless event.start!

      return unless container.can_build? event
      return if Rails.env.test?

      # Ensure prerequisites are met
      return unless ProvisionServices::ImageReadyService.new(container, event).perform

      build_result = Timeout::timeout(70) do
        container.build! event
      end

      unless build_result
        event.fail! "Failed to build container"
        return
      end

      if requested_state == 'stopped'
        event.event_details.create!(
          data: 'Requested state was stop, so we are not starting this service.',
          event_code: 'ee3be79e03dd3994'
        )
        event.done!
        return
      end

      ContainerWorkers::StartWorker.perform_async container.to_global_id.to_s, event.to_global_id.to_s
    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue Timeout::Error
      if defined?(event) && event
        event.event_details.create!(
          data: "Failed to connect to container host: Connection Timeout.",
          event_code: '91868506d445e1f2'
        )
        event.fail! 'Fatal error'
      end
    rescue Docker::Error::TimeoutError, Excon::Error::Socket, DockerSSH::ConnectionFailed => docker_timeout
      if defined?(event) && event
        if event.event_details.where(event_code: 'b4123e9e96f04555').count > 2
          event.event_details.create!(
            data: "Max connection attempts hit, halting.",
            event_code: 'b4123e9e96f04555'
          )
          event.fail! 'Timeout'
        else
          event.event_details.create!(
            data: "Timeout hit, retrying...",
            event_code: 'b4123e9e96f04555'
          )
          ContainerWorkers::ProvisionWorker.perform_in 1.minute, container_id, event_id
          return
        end
      end
      ExceptionAlertService.new(docker_timeout, 'b4123e9e96f04555')
    rescue => e
      user = nil
      if defined?(event) && event
        user = event.audit&.user
        event.event_details.create!(
          data: "Fatal Error\n#{e.message}",
          event_code: 'e6367c8012b4ae28'
        )
        event.fail! 'Fatal error'
      end
      ExceptionAlertService.new(e, 'e6367c8012b4ae28', user).perform
    end

  end
end
