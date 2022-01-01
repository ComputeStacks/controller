module LoadBalancerWorkers
  class UpdateProxyServiceWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: 'default'

    def perform(lb_id = nil)
      if lb_id.blank?
        LoadBalancer.all.each do |lb|
          LoadBalancerWorkers::UpdateProxyServiceWorker.perform_async lb.id
        end
      else
        lb = LoadBalancer.find_by(id: lb_id)
        return if lb.nil?
        lb.update_cloudflare_addresses! if lb.proxy_cloudflare
      end
    end

  end
end
