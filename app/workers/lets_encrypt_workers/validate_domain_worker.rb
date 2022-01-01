module LetsEncryptWorkers
  # Perform DNS validation on a {Deployment::ContainerDomain} and ensure it's ready for {LetsEncrypt} validation.
  class ValidateDomainWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'default' # Intentionally keeping this out of lets encrypt queue

    # @param container_domain_id [Integer] id of {Deployment::ContainerDomain}
    # @return [Boolean]
    def perform(container_domain_id = nil)

      if container_domain_id.nil?
        # Find all domains that have le_enabled, OR, are le_ready.
        # This will make sure we retroactively validate domains that were
        # previously configured for a certificate so `le_ready` is kept up to date.
        Deployment::ContainerDomain.where("system_domain = false AND ((le_enabled = true AND enabled = true) OR le_ready = true)").each do |i|
          next if i.le_ready && i.le_ready_checked > 4.days.ago

          ##
          # Only allow 2 validations per day
          next if !i.le_ready && i.event_logs.where("status = 'failed' and event_code = '971c02e9e85ad118' and created_at > ?", 1.day.ago).count > 1

          LetsEncryptWorkers::ValidateDomainWorker.perform_async i.id
        end
        return false
      end

      container_domain = Deployment::ContainerDomain.find_by(id: container_domain_id)
      return false if container_domain.nil?

      return false if container_domain.system_domain
      return false if container_domain.container_service.nil?
      return false if container_domain.container_service.load_balancer.nil?

      event = container_domain.event_logs.find_by(event_code: '971c02e9e85ad118', status: 'pending')

      ##
      # If we're coming from an existing event, it means there was a DNS connection error.
      # If we have more than 2 failed attempts, then halt future tries and flag domain as invalid
      if event
        if container_domain.event_details.where('event_log_data.event_code = ? AND event_log_data.created_at > ?', 'afb5d727910b5954', 30.minutes.ago).count > 2
          container_domain.update(
            le_ready: false,
            le_ready_checked: Time.now,
            sys_no_reload: true,
            skip_validation: true
          )
          event.event_details.create!(
            data: "Too many failed attempts to contact DNS server, halting future validations.",
            event_code: '119b1bac720a4f15'
          )
          event.fail! 'Too many failed attempts'
          return
        end
        event.start!
      else
        audit = Audit.create_from_object!(container_domain, 'updated', '127.0.0.1')
        event = EventLog.create!(
          locale: 'lets_encrypt.validate',
          locale_keys: { domain: container_domain.domain },
          audit: audit,
          status: 'running',
          event_code: '971c02e9e85ad118'
        )
        event.container_domains << container_domain
        event.container_services << container_domain.container_service if container_domain.container_service
        event.deployments << container_domain.deployment if container_domain.deployment
      end

      is_valid = LetsEncryptServices::ValidateDomainService.new(container_domain, event).perform

      ##
      # If we get a `Dnsruby::Refused`, don't immediately flag this as invalid.
      # Try the job again
      event.reload
      dns_refused_events = event.event_details.where(event_code: 'afb5d727910b5954').count
      if dns_refused_events > 0 && dns_refused_events < 4
        event.pending!
        LetsEncryptWorkers::ValidateDomainWorker.perform_in(5.minutes, container_domain.id)
        return
      end

      ##
      # If:
      #   * Failed current validation
      #   * Came here already in a failed validation state
      #   * Have 11 failed validation events in the last 8 days
      # Then:
      #   * Disable future validation attempts until manually re-enabled
      if !is_valid && !container_domain.le_ready && container_domain.event_logs.where("status = 'failed' and event_code = '971c02e9e85ad118' and created_at > ?", 8.days.ago).count > 11
        event.event_details.create!(
          data: "Too many failed validation attempts within the past week, cancelling LetsEncrypt request.\n\nPlease edit the domain and re-enable LetsEncrypt to restart the validation process.",
          event_code: '149a6992a399ba9f'
        )
        container_domain.update(
          le_enabled: false,
          sys_no_reload: true,
          skip_validation: true
        )
      else
        container_domain.update(
          le_ready: (is_valid.nil? ? false : is_valid),
          le_ready_checked: Time.now,
          sys_no_reload: true,
          skip_validation: true
        )
      end
      is_valid.nil? ? false : is_valid
    rescue => e
      ExceptionAlertService.new(e, 'a870f065c51cd74f').perform
    end

  end
end
