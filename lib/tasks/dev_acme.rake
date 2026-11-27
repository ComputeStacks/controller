namespace :dev do
  desc "Point ACME at the compose pebble and use the fake `exec` DNS provider (dev only)"
  task acme_pebble: :environment do
    abort "dev:acme_pebble is for development only." if Rails.env.production?

    port = ENV["ACME_API_PORT"].presence
    abort "ACME_API_PORT is not set; run this where mise has loaded .envrc." if port.nil?
    pebble = "https://#{ENV.fetch("DOCKER_IP", "localhost")}:#{port}/dir"
    letsencrypt = %w[
      https://acme-v02.api.letsencrypt.org/directory
      https://acme-staging-v02.api.letsencrypt.org/directory
    ]

    # Only replace values that are unset or still the stock defaults, so a
    # developer who configured a real provider or directory keeps it.
    Setting.acme_directory
    dir = Setting.find_by(name: "acme_directory")
    if dir.value.blank? || letsencrypt.include?(dir.value)
      dir.update!(value: pebble)
      puts "acme_directory -> #{pebble}"
    else
      puts "acme_directory left as #{dir.value}"
    end

    Setting.le_dns_provider
    provider = Setting.find_by(name: "le_dns_provider")
    if provider.value.blank?
      provider.update!(value: "exec")
      puts "le_dns_provider -> exec"
    else
      puts "le_dns_provider left as #{provider.value}"
    end

    if provider.value == "exec"
      Setting.le_dns_provider_secret
      secret = Setting.find_by(name: "le_dns_provider_secret")
      if secret.decrypted_value.blank?
        # exec runs /bin/true instead of writing a TXT record; pebble accepts
        # every challenge (PEBBLE_VA_ALWAYS_VALID), and with no record there
        # is nothing to wait for.
        secret.value = "EXEC_PATH=/bin/true\nCERT_ISSUER_INSECURE_SKIP_PROPAGATION_CHECK=1"
        secret.save!
        puts "le_dns_provider_secret -> EXEC_PATH=/bin/true + skip propagation check"
      else
        puts "le_dns_provider_secret left as is"
      end
    end

    Setting.le_dns_alias_zone
    zone = Setting.find_by(name: "le_dns_alias_zone")
    if zone.value.present?
      puts "le_dns_alias_zone is #{zone.value}: every load balancer needs its _acme-challenge CNAME, which pebble dev setups don't have. Clear it unless you mean it."
    end

    if LetsEncryptServices::CertIssuerRunner.resolve_binary.nil?
      puts "cert-issuer binary not found: run lib/dev/install-cert-issuer.sh"
    end
  end
end
