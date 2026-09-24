module LoadBalancerWorkers
  class UpdateProxyServiceWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: "default"

    # Refresh the account-global CDN proxy-IP lists (Cloudflare + Bunny). The lists
    # are global, so we fetch once and redeploy every load balancer only when a
    # list actually changed (diff-before-deploy). `lb_id` is accepted for backwards
    # compatibility with older enqueues but ignored — the refresh is global.
    def perform(_lb_id = nil)
      changed = ProxyIpList.refresh!(:cloudflare)
      changed = ProxyIpList.refresh!(:bunny) || changed
      return unless changed
      LoadBalancer.find_each do |lb|
        LoadBalancerServices::DeployConfigService.new(lb).perform
      end
    end
  end
end
