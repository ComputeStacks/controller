module NetworkWorkers
  class SftpPolicyWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: 'dep_critical'

    def perform(sftp_container_id)
      service = Deployment::Sftp.find_by id: sftp_container_id
      return if service.nil?
      node = service.node
      if node.nil?
        retry_job wait: 5.minutes
        return
      end
      begin
        policy = service.calico_policy
      rescue DockerSSH::ConnectionFailed => e # Don't alert to our bug system!
        event = EventLog.create!(
          locale: 'deployment.errors.fatal',
          status: 'alert',
          notice: true,
          event_code: "7019641092d663b6"
        )
        event.event_details.create!(data: "Fatal error applying service policy: #{e.message}", event_code: '7019641092d663b6')
        event.container_services << service
        event.deployments << service.deployment
        return
      rescue => e # capture any errors from generating the policy
        ExceptionAlertService.new(e, '93547ab0b3ce1bd3').perform
        event = EventLog.create!(
          locale: 'deployment.errors.fatal',
          status: 'alert',
          notice: true,
          event_code: "93547ab0b3ce1bd3"
        )
        event.event_details.create!(data: "Fatal error applying service policy: #{e.message}", event_code: '93547ab0b3ce1bd3')
        event.container_services << service
        event.deployments << service.deployment
        return
      end
      return if Rails.env.test?
      node.host_client.client.exec!("cat <<< '#{policy.deep_stringify_keys.to_yaml}' | calicoctl apply -f -")
    end
  end
end
