module LetsEncryptServices
  ##
  # Issue a load balancer certificate with the external `cert-issuer` CLI
  # (DNS-01 through the configured DNS provider), store it, and deploy it.
  #
  #   LetsEncryptServices::CertIssuerService.new(lets_encrypt, event: nil, sweep: false).perform
  #   # => :issued | :failed | :skipped
  #
  # `sweep: true` is the scheduled renewal path: it only runs when the cert is
  # due (`can_renew?`), a DNS provider is configured, and the cert's backoff
  # (`next_attempt_at`) has passed. Every other caller ignores those.
  #
  # Failures back off on the cert row (`failure_count`, `next_attempt_at`); that
  # is written in exactly one place, the `ensure` in #perform.
  #
  class CertIssuerService
    DEADLINE = 420
    HARD_TIMEOUT = DEADLINE + 120

    CONFIG_DELAY = 6.hours
    RATE_LIMIT_FALLBACK = 1.hour
    TRANSIENT_BASE = 5.minutes
    TRANSIENT_MAX = 1.hour

    EVENT_CODE = "7a4d011518f54c6a" # Same as the HTTP-01 worker's generate/renew event
    ALIAS_MISSING_CODE = "7774fe2fd9ee5ae0"
    NO_PROVIDER_CODE = "9076e960943e75db"
    BAD_PROVIDER_ENV_CODE = "e301cb958ec90d88"
    ERROR_MESSAGE_CODE = "183626f08e5ad6fe"
    ACME_PROBLEM_CODE = "03ab0198cef814bb"
    DOMAIN_ERROR_CODE = "b1c0b47797dfe32e"
    ACCOUNT_CREATED_CODE = "b20fe441bb98b26b"
    INTERNAL_CODE = "a9c99bb811daff19"
    UNEXPECTED_CODE = "e0804d9672c9dcfe"
    ALREADY_RUNNING_CODE = "83f25a9842827a27"
    NO_DOMAINS_CODE = "b11a512a39983b21"
    DEPLOY_FAILED_CODE = "b4dc3968448ec77c"

    attr_reader :lets_encrypt, :event, :sweep, :runner

    # @param lets_encrypt [LetsEncrypt]
    # @param event [EventLog, nil] a running event to report on; one is created when nil
    # @param sweep [Boolean] true for scheduled renewals
    # @param runner [CertIssuerRunner]
    def initialize(lets_encrypt, event: nil, sweep: false, runner: CertIssuerRunner.new)
      @lets_encrypt = lets_encrypt
      @event = event
      @sweep = sweep
      @runner = runner
    end

    # @return [Symbol] :issued, :failed or :skipped
    def perform
      @outcome = nil
      @delay = nil
      @suppress_backoff = false
      @event_ready = false
      @outcome = run
    rescue => e
      @outcome = :failed
      @delay = :transient
      handle_unexpected(e)
      :failed
    ensure
      apply_backoff
    end

    private

    def run
      if sweep
        return :skipped unless lets_encrypt.can_renew?
        return :skipped if Setting.le_dns_provider.blank?
        return :skipped if lets_encrypt.next_attempt_at.present? && lets_encrypt.next_attempt_at > Time.now
      end

      domains = lets_encrypt.expected_domains
      if domains.empty?
        if event
          event.event_details.create!(data: "No domains found for this certificate.", event_code: NO_DOMAINS_CODE)
          event.cancel! "Missing domains"
        end
        return :skipped
      end
      common_name = lets_encrypt.select_common_name

      return :skipped unless claim_event!(common_name)
      return :skipped unless lets_encrypt.can_provision?(event)
      @event_ready = true

      return :failed unless preflight

      provider_env = @provider_env
      account = lets_encrypt.account
      result = runner.run(request: build_request(account, common_name, domains), env: provider_env, timeout: HARD_TIMEOUT)

      if result.ok?
        store_certificate!(result.payload, account, common_name, domains)
        :issued
      else
        handle_failure(result)
        :failed
      end
    end

    # Pick up (or create) the event under the cert's row lock, so two runs for
    # the same cert can't both start.
    # @return [Boolean]
    def claim_event!(common_name)
      busy = false
      stale = false
      lets_encrypt.with_lock do
        # with_lock reloaded the row: a sweep run re-checks that another job
        # didn't renew this cert while it waited.
        if sweep && !lets_encrypt.can_renew?
          stale = true
          next
        end
        busy = lets_encrypt.event_logs.where(status: "running").where.not(id: event&.id).exists?
        unless busy
          @event = build_event(common_name) if event.nil?
          event.lets_encrypts << lets_encrypt unless event.lets_encrypts.exists?(lets_encrypt.id)
        end
      end
      if busy && event
        event.event_details.create!(data: "Another certificate request for this certificate is already running.", event_code: ALREADY_RUNNING_CODE)
        event.cancel! "Already running"
      end
      !busy && !stale
    end

    def build_event(common_name)
      audit = Audit.create_from_object!(lets_encrypt, "updated", "127.0.0.1")
      EventLog.create!(
        locale: "lets_encrypt.#{lets_encrypt.active? ? "renew" : "generate"}",
        locale_keys: {common_name: common_name},
        status: "running",
        audit: audit,
        event_code: EVENT_CODE
      )
    end

    # @return [Boolean]
    def preflight
      if Setting.le_dns_provider.blank?
        event.event_details.create!(
          data: "No DNS provider is configured (setting le_dns_provider), so load balancer certificates cannot be issued.",
          event_code: NO_PROVIDER_CODE
        )
        event.fail! "Configuration error"
        @suppress_backoff = true
        return false
      end

      begin
        @provider_env = Setting.le_dns_provider_env
      rescue ArgumentError => e
        event.event_details.create!(data: "DNS provider credentials are invalid (setting le_dns_provider_secret): #{e.message}", event_code: BAD_PROVIDER_ENV_CODE)
        event.fail! "Configuration error"
        @delay = CONFIG_DELAY
        return false
      end

      return true if Setting.le_dns_alias_zone.blank?

      failures = []
      lets_encrypt.load_balancers.each do |lb|
        check = LetsEncryptServices::DnsAliasCheckService.new(lb)
        next if check.perform
        failures << check.failure
        check.errors.each { |err| event.event_details.create!(data: err, event_code: ALIAS_MISSING_CODE) }
      end
      return true if failures.empty?

      event.fail! "DNS Alias Missing"
      @delay = failures.all?(:lookup_error) ? :transient : CONFIG_DELAY
      false
    end

    def build_request(account, common_name, domains)
      csr = Acme::Client::CertificateRequest.new(
        common_name: common_name,
        names: domains,
        private_key: lets_encrypt.private_key
      )
      email = account.email.to_s.strip
      eab = if LetsEncryptAccount.acme_uses_eab? && account.acme_directory == LetsEncryptAccount.acme_directory
        {kid: Setting.acme_kid, hmac_key: Setting.acme_hmac_key}
      end
      {
        version: 1,
        directory_url: account.acme_directory,
        account: {
          key_pem: account.private_key.to_pem,
          email: (email.count("@") == 1) ? email : nil,
          eab: eab
        }.compact,
        csr_pem: csr.csr.to_pem,
        dns: {provider: Setting.le_dns_provider, resolvers: dns_resolvers}.compact,
        deadline_seconds: DEADLINE,
        tls_insecure_skip_verify: !Rails.env.production?
      }
    end

    # Only an operator-set RESOLVER_LIST is passed on; otherwise cert-issuer
    # uses the system resolvers.
    def dns_resolvers
      return nil if ENV["RESOLVER_LIST"].blank?
      ENV["RESOLVER_LIST"].split(",").map(&:strip).reject(&:empty?).map { |ip| ip.include?(":") ? "[#{ip}]:#{NS_PORT}" : "#{ip}:#{NS_PORT}" }
    end

    def store_certificate!(payload, account, common_name, domains)
      # Store the names we asked for: cert-issuer lowercases its `names`, and
      # can_renew? compares them exactly with expected_domains.
      lets_encrypt.update!(
        common_name: common_name,
        names: domains,
        crt: payload["certificate_pem"],
        expires_at: Time.iso8601(payload["not_after"]),
        last_generated_at: Time.now,
        failure_count: 0,
        next_attempt_at: nil
      )
      account.update_column(:account_id, payload["account_url"]) if account.account_id.blank? && payload["account_url"].present?
      if payload["account_created"]
        event.event_details.create!(data: "Registered a new ACME account with #{account.acme_directory}.", event_code: ACCOUNT_CREATED_CODE)
      end
      event.done!
      @outcome = :issued
      deploy!
    end

    def deploy!
      return if Rails.env.test?
      lets_encrypt.load_balancers.each { |lb| LoadBalancerServices::DeployConfigService.new(lb).perform }
    rescue => e
      # The certificate is stored; the next config deploy will pick it up.
      ExceptionAlertService.new(e, DEPLOY_FAILED_CODE).perform
    end

    def handle_failure(result)
      error = result.error
      message = error["message"].presence || "cert-issuer failed (#{result.error_type})"
      event.event_details.create!(data: message, event_code: ERROR_MESSAGE_CODE)
      problem = error["acme_problem"]
      if problem.is_a?(Hash) && problem["detail"].present?
        event.event_details.create!(data: "ACME: #{problem["detail"]}", event_code: ACME_PROBLEM_CODE)
      end

      case result.error_type
      when "config"
        event.fail! "Configuration error"
        @delay = CONFIG_DELAY
      when "validation_failed"
        domain_errors = error["domains"].is_a?(Hash) ? error["domains"] : {}
        domain_errors.each do |name, info|
          detail = info.is_a?(Hash) ? info["message"] : info
          event.event_details.create!(data: "#{name}: #{detail}", event_code: DOMAIN_ERROR_CODE)
        end
        event.fail! "Validation failed"
        @delay = CONFIG_DELAY
      when "rate_limited"
        event.fail! "Rate limited"
        @delay = rate_limit_delay(error["retry_after"])
      when "transient"
        event.fail! "Transient error"
        @delay = :transient
      else # internal
        tail = result.stderr_tail.to_s
        ExceptionAlertService.new(RuntimeError.new("cert-issuer internal error: #{message}\n#{tail}"), INTERNAL_CODE).perform
        event.event_details.create!(data: "cert-issuer internal error: #{message}\n\n#{tail}".strip, event_code: INTERNAL_CODE) if tail.present?
        event.fail! "Fatal Error"
        @delay = :transient
      end
    end

    def rate_limit_delay(retry_after)
      return RATE_LIMIT_FALLBACK if retry_after.blank?
      seconds = Time.iso8601(retry_after) - Time.now
      (seconds > 0) ? seconds : RATE_LIMIT_FALLBACK
    rescue ArgumentError
      RATE_LIMIT_FALLBACK
    end

    def handle_unexpected(e)
      ExceptionAlertService.new(e, UNEXPECTED_CODE).perform
      return unless event
      ev = EventLog.find_by(id: event.id)
      return if ev.nil?
      ev.event_details.create!(data: "Fatal Error: #{e.message}", event_code: UNEXPECTED_CODE)
      ev.fail! "Fatal Error"
      @event_ready = true
    rescue => inner
      Rails.logger.error "[CertIssuerService] error while handling failure for LetsEncrypt #{lets_encrypt&.id}: #{inner.class}"
    end

    def apply_backoff
      return unless @event_ready
      return if @suppress_backoff
      return if @outcome == :issued || @outcome == :skipped
      count = lets_encrypt.failure_count.to_i + 1
      delay = @delay.nil? || @delay == :transient ? transient_delay(count) : @delay
      lets_encrypt.update_columns(failure_count: count, next_attempt_at: Time.now + delay)
    end

    def transient_delay(count)
      [TRANSIENT_BASE * 2**(count - 1).clamp(0, 10), TRANSIENT_MAX].min
    end
  end
end
