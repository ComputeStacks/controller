module LoadBalancers
  module CloudflareProxyAddresses
    extend ActiveSupport::Concern

    included do
      after_update :set_cloudflare_ips
      after_create_commit :update_cloudflare_addresses!
    end

    # Remotely fetch a list of all CloudFlare IPs and merge the results with our local database
    def update_cloudflare_addresses!
      return nil unless proxy_cloudflare
      ipv4 = HTTParty.get('https://www.cloudflare.com/ips-v4').body.split("\n")
      ipv6 = HTTParty.get('https://www.cloudflare.com/ips-v6').body.split("\n")

      ipv4 = [] unless ipv4.is_a?(Array)
      ipv6 = [] unless ipv6.is_a?(Array)

      return nil if ipv4.empty? || ipv6.empty? # Something went wrong, we'll try later.

      errors = []
      ipaddrs.tagged_with('cloudflare').delete_all
      (ipv4 + ipv6).each do |ip|
        addr = ipaddrs.new(role: 'proxy', ip_addr: ip, label: 'Cloudflare')
        addr.tag_list = "cloudflare"
        errors << addr.errors.full_messages unless addr.save
      end
      unless errors.empty?
        SystemEvent.create!(
          message: "Error Saving CloudFlare IPs to Load Balancer: #{name}",
          log_level: 'warn',
          data: {
            'lb' => {
              'id' => id,
              'name' => name
            },
            'errors' => errors.join(', ')
          },
          event_code: 'be605e86063d5ee8'
        )
      end
      LoadBalancerServices::DeployConfigService.new(self).perform if errors.empty?
      errors.empty?
    rescue => e
      ExceptionAlertService.new(e, 'b15567c2e9abab63').perform
      nil
    end

    private

    # When toggling `proxy_cloudflare`, update the Load Balancer.
    def set_cloudflare_ips
      if saved_change_to_attribute?("proxy_cloudflare")
        if proxy_cloudflare
          LoadBalancerWorkers::UpdateProxyServiceWorker.perform_async id
        else
          ipaddrs.tagged_with('cloudflare').delete_all
          LoadBalancerServices::DeployConfigService.new(self).perform
        end
      end
    end

  end
end
