module ContainerWorkers
  class RebuildWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # args[0] = container_id GLOBALID
    # args[1] = event_id GLOBALID
    # args[2] = keep_last_power_state (default FALSE). If rebuilding, new state will be ON.
    def perform(*args)
      timeout_event_code = '2f4eeefceb3fd59e' # Container Stop
      container = GlobalID::Locator.locate args[0]
      event = GlobalID::Locator.locate args[1]
      keep_prev_state = args[2].nil? ? false : args[2]

      return if container.nil? || event.nil?

      return unless event.start!

      # Ensure prerequisites are met
      return unless ProvisionServices::ImageReadyService.new(container, event).perform

      container_state = if keep_prev_state
                          container.req_state == 'stopped' ? 'stopped' : 'running'
                        else
                          'running'
                        end

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

      if container.region.has_clustered_networking?
        if container.is_a?(Deployment::Container)
          NetworkWorkers::ServicePolicyWorker.perform_async container.service&.id
        elsif container.is_a?(Deployment::Sftp)
          NetworkWorkers::SftpPolicyWorker.perform_async container.id
        end
      end

      ContainerWorkers::ProvisionWorker.perform_in 5.seconds, container.to_global_id.to_s, event.to_global_id.to_s, container_state

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
