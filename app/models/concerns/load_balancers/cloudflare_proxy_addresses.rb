module LoadBalancers
  module CloudflareProxyAddresses
    extend ActiveSupport::Concern

    included do
      after_update :set_cloudflare_ips
      after_create_commit :ensure_cloudflare_addresses!
    end

    # Refresh the account-global Cloudflare IP list file (shared by all load
    # balancers) and redeploy this LB if the list actually changed.
    # @return [Boolean, nil]
    def update_cloudflare_addresses!
      return nil unless proxy_cloudflare
      changed = ProxyIpList.refresh!(:cloudflare)
      LoadBalancerServices::DeployConfigService.new(self).perform if changed
      changed
    end

    private

    # On create / toggle-on: make sure the global list file exists (fetch it if a
    # fresh install hasn't populated it yet), then deploy this LB so it picks it up.
    def ensure_cloudflare_addresses!
      return unless proxy_cloudflare
      # Populate the global list asynchronously if missing — never block the
      # request/transaction on outbound HTTP from inside a model callback.
      LoadBalancerWorkers::UpdateProxyServiceWorker.perform_async unless ProxyIpList.file_present?(:cloudflare)
      LoadBalancerServices::DeployConfigService.new(self).perform
    end

    # When toggling `proxy_cloudflare`, redeploy this Load Balancer.
    def set_cloudflare_ips
      return unless saved_change_to_attribute?("proxy_cloudflare")
      if proxy_cloudflare
        ensure_cloudflare_addresses!
      else
        LoadBalancerServices::DeployConfigService.new(self).perform
      end
    end
  end
end
