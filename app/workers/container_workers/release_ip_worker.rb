module ContainerWorkers
  class ReleaseIpWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # @param [String] container_id GlobalID of container ID
    # @param [String] event_id GlobalID
    def perform(container_id, event_id)
      container = GlobalID::Locator.locate container_id
      event = GlobalID::Locator.locate event_id

      begin
        net_client = container.ip_address.network.docker_client container.node
        net_client.disconnect(container.name, {}, { 'Force' => true })
        Network::Cidr.release! container.node, container.ip_address.cidr.to_s
      rescue => e
        ExceptionAlertService.new(e, '674eb0d17ca30102').perform
        # Ignore and drop any errors
      end

      ContainerWorkers::StartWorker.perform_in 10.seconds, container_id, event_id
    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue Docker::Error::TimeoutError, DockerSSH::ConnectionTimeout
      ContainerWorkers::ReleaseIpWorker.perform_in(30.seconds, container_id, event_id)
    rescue => e
      user = nil
      if defined?(container) && container && defined?(event) && event
        if e.message =~ /is not connected to network/
          # Allow to proceed if it's already disconnected.
          ContainerWorkers::StartWorker.perform_async container_id, event_id
          return
        else
          event.event_details.create!(
            data: 'Error recovering from ip in use',
            event_code: 'cc40061553c02457'
          )
          event.event_details.create!(
            data: "Fatal error:\n#{e.message}",
            event_code: '44fdde78cb3975eb'
          )
          event.fail! 'Fatal error'
        end
        user = event.audit&.user
      end
      ExceptionAlertService.new(e, '44fdde78cb3975eb', user).perform
    end

  end
end
