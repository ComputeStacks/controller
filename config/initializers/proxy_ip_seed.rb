# Seed the global CDN proxy-IP list files on boot if they don't exist yet.
# Handles fresh installs (and the first boot after deploying the file-based
# handler) so the lists aren't empty until the daily Clockwork refresh runs.
# Idempotent: once the files exist this is just a couple of File.exist? checks.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  begin
    if defined?(ProxyIpList) && ProxyIpList.any_missing?
      LoadBalancerWorkers::UpdateProxyServiceWorker.perform_async
    end
  rescue => e
    Rails.logger.warn("proxy_ip_seed skipped: #{e.message}")
  end
end
