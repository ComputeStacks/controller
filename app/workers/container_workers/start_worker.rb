module ContainerWorkers
  class StartWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # @param [String] container_id Global ID
    # @param [String] event_id Global
    def perform(container_id, event_id)
      return if event_id.nil?
      container = GlobalID::Locator.locate container_id
      event = GlobalID::Locator.locate event_id

      return unless event.start!

      result = Timeout::timeout(30) do
        container.start! event
      end

      if result
        if container.is_a?(Deployment::Container) # SFTP will also use this job
          container.volumes.each do |vol|
            vol.update_consul!
          end
        end
      end
    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue Timeout::Error
      if defined?(event) && event
        event.event_details.create!(
          data: "Failed to connect to container host: Connection Timeout.",
          event_code: '8fff98d4266d77ac'
        )
        event.fail! 'Fatal error'
      end
    rescue => e
      user = nil
      if defined?(event) && event
        user = event.audit&.user
        event.event_details.create!(
          data: "Fatal Error\n#{e.message}",
          event_code: '520517bc1b0300fb'
        )
        event.fail! 'Fatal error'
      end
      ExceptionAlertService.new(e, '520517bc1b0300fb', user).perform
    end

  end
end
