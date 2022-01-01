module ContainerWorkers
  class RebuildWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # @param [String] container_id Global ID
    # @param [String] event_id Global
    def perform(container_id, event_id)
      timeout_event_code = '2f4eeefceb3fd59e' # Container Stop
      return if event_id.nil?
      container = GlobalID::Locator.locate container_id
      event = GlobalID::Locator.locate event_id

      return unless event.start!

      # Ensure prerequisites are met
      return unless ProvisionServices::ImageReadyService.new(container, event).perform


      stop_result = Timeout::timeout(30) do
        container.stop!(event, true)
      end

      unless stop_result
        event.event_details.create!(
          data: 'Failed to stop container, rebuild halted.',
          event_code: 'a8f31c4c9204a78d'
        )
        event.fail! 'Unable to stop container'
        return
      end

      timeout_event_code = '59220f69d6baf10f' # Deletion
      delete_result = Timeout::timeout(30) do
        container.delete_from_node! event
      end

      unless delete_result
        event.event_details.create!(
          data: 'Failed to delete container, rebuild halted.',
          event_code: '60c2aa9d414a1817'
        )
        event.fail! 'Unable to delete container'
        return
      end

      if container.is_a?(Deployment::Container)
        NetworkWorkers::ServicePolicyWorker.perform_async container.service&.id
      elsif container.is_a?(Deployment::Sftp)
        NetworkWorkers::SftpPolicyWorker.perform_async container.id
      end

      ContainerWorkers::ProvisionWorker.perform_in 5.seconds, container_id, event_id

    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue Timeout::Error
      if defined?(event) && event
        event.event_details.create!(
          data: "Failed to connect to container host: Connection Timeout.",
          event_code: timeout_event_code
        )
        event.fail! 'Fatal error'
      end
    rescue => e
      user = nil
      if defined?(event) && event
        user = event.audit&.user
        event.event_details.create!(
          data: "Fatal Error\n#{e.message}",
          event_code: '2eadb7f57a7a3300'
        )
        event.fail! 'Fatal error'
      end
      ExceptionAlertService.new(e, '2eadb7f57a7a3300', user).perform
    end

  end
end
