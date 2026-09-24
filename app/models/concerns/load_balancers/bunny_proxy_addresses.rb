module LoadBalancers
  module BunnyProxyAddresses
    extend ActiveSupport::Concern

    included do
      after_update :set_bunny_ips
      after_create_commit :ensure_bunny_addresses!
    end

    # Refresh the account-global Bunny IP list file (shared by all load balancers)
    # and redeploy this LB if the list actually changed.
    # @return [Boolean, nil]
    def update_bunny_addresses!
      return nil unless proxy_bunny
      changed = ProxyIpList.refresh!(:bunny)
      LoadBalancerServices::DeployConfigService.new(self).perform if changed
      changed
    end

    private

    # On create / toggle-on: make sure the global list file exists (fetch it if a
    # fresh install hasn't populated it yet), then deploy this LB so it picks it up.
    def ensure_bunny_addresses!
      return unless proxy_bunny
      # Populate the global list asynchronously if missing — never block the
      # request/transaction on outbound HTTP from inside a model callback.
      LoadBalancerWorkers::UpdateProxyServiceWorker.perform_async unless ProxyIpList.file_present?(:bunny)
      LoadBalancerServices::DeployConfigService.new(self).perform
    end

    # When toggling `proxy_bunny`, redeploy this Load Balancer.
    def set_bunny_ips
      return unless saved_change_to_attribute?("proxy_bunny")
      if proxy_bunny
        ensure_bunny_addresses!
      else
        LoadBalancerServices::DeployConfigService.new(self).perform
      end
    end
  end
end
