module LoadBalancerWorkers
  class DeployConfigWorker
    include Sidekiq::Worker
    sidekiq_options retry: 1, queue: 'default'

    def perform(lb_id = nil)
      load_balancers = lb_id.nil? ? LoadBalancer.all : [GlobalID::Locator.locate(lb_id)]
      load_balancers.each do |lb|
        LoadBalancerServices::UpdateBalancerService.new(lb).perform
      end
    rescue ActiveRecord::RecordNotFound
      return
    rescue DockerSSH::ConnectionFailed => e
      SystemEvent.create!(
        message: "LoadBalancer Config Failure",
        log_level: 'warn',
        data: {
          'load_balancer' => lb_id,
          'errors' => e.message
        },
        event_code: '9dd8d4e0fab444f0'
      )
    rescue => e
      ExceptionAlertService.new(e, '270ce7866365f48a').perform
    end

  end
end
