module LetsEncryptWorkers
  ##
  # Generate a LetsEncrypt certificate
  #
  class GenerateCertWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'letsencrypt'

    # @param lets_encrypt_id [Integer] id of {LetsEncrypt}
    # @param event_id [Integer] id of {EventLog}
    def perform(lets_encrypt_id, event_id = nil)

      if lets_encrypt_id.nil?
        return unless Setting.le_auto_enabled?
        LetsEncrypt.all.each do |le|
          next unless le.can_renew?
          next if le.event_logs.where(status: 'running').exists?
          LetsEncryptWorkers::GenerateCertWorker.perform_async le.id
        end
        return
      end

      event = event_id.nil? ? nil : EventLog.find_by(id: event_id, status: 'running')

      unless Setting.le_auto_enabled?
        event.cancel! 'Provisioning temporarily disabled' if event
        return
      end

      lets_encrypt = LetsEncrypt.find_by(id: lets_encrypt_id)
      return false if lets_encrypt.nil?

      # Dont try to generate at the same time!
      return false if lets_encrypt.event_logs.where(status: 'running').exists?

      account_client = lets_encrypt.account.client
      return false if account_client.nil?

      domains = lets_encrypt.expected_domains
      if domains.empty?
        if event
          event.event_details.create!(data: "No domains found, removing certificate", event_code: '49f63167e410c038')
          event.cancel! 'Missing domains'
        end
        reload_load_balancer!(lets_encrypt)
        lets_encrypt.destroy
        return false
      end

      # Select our common_name. Defaults to the one already stored, as long as it still exists in the available names. Otherwise, we set it ourselves.
      common_name = lets_encrypt.select_common_name

      event = build_event(lets_encrypt, common_name) if event.nil?
      return false if event.nil?

      return false unless lets_encrypt.can_provision?(event)

      order = account_client.new_order(identifiers: domains)

      order.authorizations.each do |auth|
        next unless auth.status == 'pending' # It may already be valid!
        domain = auth.domain
        # auth_domain = auth.wildcard ? "*.#{auth.domain}" : auth.domain
        auth_request = lets_encrypt.lets_encrypt_auths.create!(domain: auth.domain)
        if auth.wildcard
          auth_challenge = auth.dns
          primary_domain = auth_request.dns_zone
          if primary_domain.nil?
            event.event_details.create!(
              data: "Unable to validate #{domain} using DNS: No local zone file found.",
              event_code: '0994c35516f37636'
            )
            event.fail! 'Missing zone file'
            break
          end
          unless primary_domain.system_can_update?
            event.event_details.create!(
              data: "Unable to modify DNS Zone file for #{domain}: You have uncommitted changes. Please save them, or revert the zone file to the copy from the DNS server.",
              event_code: '710c75e09bec15ed'
            )
            event.fail! 'Dirty Zone File State'
            break
          end
          auth_request.update(
            challenge_type: 'dns',
            record_name: auth_challenge.record_name,
            record_type: auth_challenge.record_type,
            record_content: auth_challenge.record_content,
            expires_at: auth.expires
          )
          dns_challenge = LetsEncryptServices::DnsChallengeService.new(auth_request, event)
          unless dns_challenge.perform
            event.fail! 'DNS Challenge Failed'
            break
          end
          # You can only request dns validation once, so we need to allow some time to process
          sleep(Setting.le_dns_sleep)
          auth_challenge.reload
        else # HTTP Auth
          auth_challenge = auth.http
          auth_request.update(
            challenge_type: 'http',
            token: auth_challenge.token,
            content: auth_challenge.file_content,
            expires_at: auth.expires
          )
        end

        auth_challenge.request_validation
        challenge_timeout = (Rails.env.test? ? 5.seconds.from_now : 4.minutes.from_now).to_time
        while auth_challenge.status == 'pending' && (Time.now < challenge_timeout)
          sleep(1)
          auth_challenge.reload
        end

        # Handle a failed validation
        unless auth_challenge.status == 'valid'
          # Remove from domain list, remove valid status on domain, and log error.
          if auth.wildcard
            LetsEncryptServices::ValidationResponseService.new(
              nil, domain, auth_challenge.error, event
            ).perform
          else
            container_domain = Deployment::ContainerDomain.find_by(domain: domain)
            event.container_domains << container_domain if container_domain
            LetsEncryptServices::ValidationResponseService.new(
              container_domain, domain, auth_challenge.error, event
            ).perform
          end
          # Remove the failed domain from the list of valid domains.
          domains.delete domain
          if domains.empty?
            # If we no longer have any domains, then kill this job
            event.cancel! 'Missing domains'
            break
          end
          # If our common name failed, then we need to set a new ones
          if common_name == auth.domain
            common_name = domains[0]
          end
        end
      end

      return false if event.failed?

      order.reload

      ##
      # Wait for order to become ready
      ready_timeout = (Rails.env.test? ? 5.seconds.from_now : 1.minute.from_now).to_time
      while order.status == 'pending' && (Time.now < ready_timeout)
        sleep(1)
        order.reload
      end

      # Capture invalid orders
      unless %(valid ready).include?(order.status)
        event.event_details.create!(
          data: "Order status '#{order.status.capitalize}' is not acceptable for certificate generation.\n\nPlease double check that your domains are pointing to the correct IP Address.",
          event_code: '58954675505e9251'
        )
        event.update_attribute :status, 'failed'
        return false
      end

      csr = Acme::Client::CertificateRequest.new(
        common_name: common_name,
        names: domains,
        private_key: lets_encrypt.private_key
      )
      order.finalize(csr: csr)

      order_timeout = (Rails.env.test? ? 5.seconds.from_now : 2.minutes.from_now).to_time
      while order.status == 'processing' && (Time.now < order_timeout)
        sleep(1)
        order.reload
      end

      certificate = order.certificate
      crt_info = OpenSSL::X509::Certificate.new certificate

      lets_encrypt.update(
        common_name: common_name,
        last_generated_at: Time.now,
        expires_at: crt_info.not_after,
        names: domains,
        crt: certificate
      )
      event.done!
      reload_load_balancer!(lets_encrypt)
    rescue Acme::Client::Error::RateLimited => e
      ExceptionAlertService.new(e, '47b83c8e56a5b18e').perform
      if defined?(event) && event # Should never be null!
        case e.message
        when /too many certificates already issued for exact set of domains/
          event.event_details.create!(
            data: "LetsEncrypt RateLimited: #{e.message}",
            event_code: 'bdd38ea038297c94'
          )
          event.event_details.create!(
            data: domains.join(','),
            event_code: 'dc53ef4622c4ef86'
          ) if defined?(domains) && domains.is_a?(Array)
        when /too many failed authorizations recently/
          event.event_details.create!(
            data: "LetsEncrypt RateLimited: #{e.message}",
            event_code: '45ab6fff7c170d0f'
          )
        else
          event.event_details.create!(
            data: "LetsEncrypt RateLimited: #{e.message}",
            event_code: '47b83c8e56a5b18e'
          )
        end
        event.fail! 'Fatal Error'
      end
    rescue Acme::Client::Error::AccountDoesNotExist => e
      # Noticed this in testing, should neve happen in prod, but good to recover from it if it does.
      ExceptionAlertService.new(e, '3f96f9ca70bb5017').perform # Lets track that this happened...
      return false if account_client.nil? # err, something strange!
      # 1. Delete the old `kid` reference in the current account
      lets_encrypt.account.update_column :account_id, nil
      # 2. # regen our account
      if lets_encrypt.account.setup!
        # 3. try this again!
        event_id = defined?(event) && event ? event.id : nil
        if defined?(event) && event
          event.event_details.create!(
            data: "LetsEncrypt Account error, retrying...",
            event_code: '3f96f9ca70bb5017'
          )
        end
        LetsEncryptWorkers::GenerateCertWorker.perform_async lets_encrypt_id, event_id
      else # Major issues, just stop issuing this cert
        if defined?(event) && event
          event.event_details.create!(
            data: "Fatal LetsEncrypt error, contact support",
            event_code: 'ef1da605ec1b3927'
          )
          event.fail! 'Fatal Error'
        end
        return false
      end
    rescue Acme::Client::Error::Timeout => e
      # ExceptionAlertService.new(e, '9698a88bf5a6ef93').perform
      event_id = defined?(event) && event ? event.id : nil
      if defined?(event) && event
        event.event_details.create!(
          data: "LetsEncrypt Server Timeout. Will retry in 2 minutes.\n\n#{e.message}",
          event_code: '9698a88bf5a6ef93'
        )
      end
      LetsEncryptWorkers::GenerateCertWorker.perform_in 2.minute, lets_encrypt_id, event_id
    rescue Acme::Client::Error::Malformed => e # JWS verification error (saw this in staging.), just retry and it will work.
      # ExceptionAlertService.new(e, '49f13e65b274f33e').perform
      event_id = defined?(event) && event ? event.id : nil
      if defined?(event) && event
        event.event_details.create!(
          data: "Fatal Error. Will retry in 2 minutes.\n\n#{e.message}",
          event_code: '1942ae92e3512794'
        )
      end
      LetsEncryptWorkers::GenerateCertWorker.perform_in 2.minute, lets_encrypt_id, event_id
    rescue Acme::Client::Error::ServerInternal => e # More random LE errors: `Error creating new order`
      # ExceptionAlertService.new(e, 'f5c13f88f34473a8').perform
      event_id = defined?(event) && event ? event.id : nil
      if defined?(event) && event
        event.event_details.create!(
          data: "LetsEncrypt Service Error. Will retry in 2 minutes.\n\n#{e.message}",
          event_code: 'f5c13f88f34473a8'
        )
      end
      LetsEncryptWorkers::GenerateCertWorker.perform_in 2.minute, lets_encrypt_id, event_id
    rescue => e
      ExceptionAlertService.new(e, '49f13e65b274f33e').perform
      if defined?(event) && event
        event.event_details.create!(
          data: "Fatal Error: #{e.message}",
          event_code: '49f13e65b274f33e'
        )
        event.fail! 'Fatal Error'
      end
    ensure
      if defined?(event) && event
        event.reload
        case event.status
        when 'running'
          event.fail! 'Fatal Error'
        when 'trash'
          event.destroy
        end
      end
    end

    private

    def build_event(lets_encrypt, common_name)
      audit = Audit.create_from_object!(lets_encrypt, 'updated', '127.0.0.1')
      event = EventLog.new(
        locale: "lets_encrypt.#{lets_encrypt.active? ? 'renew' : 'generate'}",
        locale_keys: { common_name: common_name },
        status: 'running',
        audit: audit,
        event_code: '7a4d011518f54c6a'
      )
      if event.save
        event.lets_encrypts << lets_encrypt if lets_encrypt
        event
      else
        nil
      end
    end

    def reload_load_balancer!(lets_encrypt)
      lbs = if lets_encrypt.user.nil? && !lets_encrypt.load_balancers.empty?
        lets_encrypt.load_balancers
      elsif lets_encrypt.user.nil?
        LoadBalancer.all
      else
        lets_encrypt.user.load_balancers
      end
      unless Rails.env.test?
        # TODO: How do we test this?
        lbs.each { |lb| LoadBalancerServices::DeployConfigService.new(lb).perform }
      end
    end

  end
end
