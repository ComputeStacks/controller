module NetworkWorkers
  class ServicePolicyWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: 'dep_critical'

    def perform(service_id)
      service = Deployment::ContainerService.find_by(id: service_id)
      return false if service.nil?
      node = service.region.nodes.online.first
      if node.nil?
        retry_job wait: 5.minutes
        return false
      end
      return true unless service.region.has_clustered_networking?
      begin
        policy = service.calico_policy
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
        return false
      end
      node.host_client.client.exec!("cat <<< '#{policy.deep_stringify_keys.to_yaml}' | calicoctl apply -f -")
    end
  end
end
