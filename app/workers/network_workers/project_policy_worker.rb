module NetworkWorkers
  class ProjectPolicyWorker
    include Sidekiq::Worker

    sidekiq_options retry: 2, queue: 'dep'

    def perform(project_id)
      project = GlobalID::Locator.locate project_id
      return false if project.nil?
      project.regions.each do |region|
        next unless region.has_clustered_networking?
        node = region.nodes.online.first
        if node.nil?
          project.event_logs.create!(
            status: 'alert',
            notice: true,
            state_reason: "Unable to connect to node. None are online.",
            locale: 'deployment.errors.fatal',
            event_code: '10f5d8b6ecb75f1c'
          )
          return false
        end
        node.host_client.client.exec!("cat <<< '#{project.calico_policy.deep_stringify_keys.to_yaml}' | calicoctl apply -f -")
      end
    rescue ActiveRecord::RecordNotFound
      return
    rescue DockerSSH::ConnectionFailed => e # Don't alert to our bug system!
      project.event_logs.create!(
        status: 'alert',
        notice: true,
        state_reason: e.message,
        locale: 'deployment.errors.fatal',
        event_code: 'eaf3bb0eb79e7e90'
      ) if defined?(project) && project
    rescue => e
      ExceptionAlertService.new(e, '5f6b98d19109b08c').perform
      project.event_logs.create!(
        status: 'alert',
        notice: true,
        state_reason: e.message,
        locale: 'deployment.errors.fatal',
        event_code: '5f6b98d19109b08c'
      ) if defined?(project) && project
    end

  end
end
