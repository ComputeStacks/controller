namespace :lets_encrypt do
  desc "Issue a load balancer certificate now with cert-issuer: rake \"lets_encrypt:issue_lb[<lb_id>|all]\""
  task :issue_lb, [:target] => :environment do |_t, args|
    target = args[:target].to_s.strip
    if target.blank?
      warn 'Usage: rake "lets_encrypt:issue_lb[<lb_id>|all]"'
      exit 1
    end
    if Setting.le_dns_provider.blank?
      warn "No DNS provider is configured (setting le_dns_provider). Set it, and its credentials, before issuing load balancer certificates."
      exit 1
    end

    lbs = if target == "all"
      LoadBalancer.where(le: true).order(:id).to_a
    else
      lb = LoadBalancer.find_by(id: target)
      if lb.nil?
        warn "Load balancer #{target} not found."
        exit 1
      end
      [lb]
    end

    failed = false
    lbs.each do |lb|
      unless lb.le
        puts "LB #{lb.id} (#{lb.domain}): automatic certificates are disabled for this load balancer, skipping."
        next
      end

      cert = lb.lets_encrypt
      if cert.nil?
        cert = LetsEncrypt.create!(user_id: nil, account: LetsEncryptAccount.find_or_create)
        lb.update(lets_encrypt: cert)
      end

      audit = Audit.create_from_object!(lb, "updated", "127.0.0.1")
      event = EventLog.create!(
        locale: "load_balancers.generate_lets_encrypt",
        locale_keys: {load_balancer: lb.label},
        status: "running",
        audit: audit,
        event_code: "f68bcf5786036bf2"
      )
      event.load_balancers << lb

      # Same account switch the worker does when acme_directory has changed.
      cert.update(account: LetsEncryptAccount.find_or_create) unless cert.has_default_acme_provider?

      outcome = LetsEncryptServices::CertIssuerService.new(cert, event: event, sweep: false).perform
      failed ||= outcome != :issued

      event = EventLog.find_by(id: event.id)
      status = event ? "#{event.status}#{" (#{event.state_reason})" if event.state_reason.present?}" : "removed"
      puts "LB #{lb.id} (#{lb.domain}): #{outcome}, event #{status}"
      event&.event_details&.order(:id)&.each { |d| puts "  - #{d.data}" }
    end

    exit 1 if failed
  end
end
