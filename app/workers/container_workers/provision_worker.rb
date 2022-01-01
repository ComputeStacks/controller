module ContainerWorkers
  class ProvisionWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # @param [String] container_id Global ID
    # @param [String] event_id Global
    def perform(container_id, event_id)
      container = GlobalID::Locator.locate container_id
      event = GlobalID::Locator.locate event_id

      return unless event.start!

      return unless container.can_build? event
      return if Rails.env.test?

      # Ensure prerequisites are met
      return unless ProvisionServices::ImageReadyService.new(container, event).perform

      build_result = Timeout::timeout(30) do
        container.build! event
      end

      unless build_result
        event.fail! "Failed to build container"
        return
      end

      ContainerWorkers::StartWorker.perform_async container_id, event_id

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
