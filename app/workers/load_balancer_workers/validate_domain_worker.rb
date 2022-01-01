module LoadBalancerWorkers
  # Validate that the domain supplied to the load balancer is setup correctly
  class ValidateDomainWorker
    include Sidekiq::Worker
    sidekiq_options retry: 4, queue: 'default'

    # @param load_balancer_id [Integer] id of {LoadBalancer}
    # @param audit_id [Integer] id of {Audit}
    def perform(load_balancer_id, audit_id = nil)
      lb = LoadBalancer.find_by(id: load_balancer_id)
      return if lb.nil?
      return if lb.domain.blank?
      audit = if audit_id.nil?
        Audit.create_from_object!(lb, 'updated', '127.0.0.1')
      else
        Audit.find_by(id: audit_id)
      end
      return false if audit.nil?

      event = EventLog.create!(
        audit: audit,
        locale: 'load_balancers.validate_domain',
        locale_keys: {
          domain: lb.domain,
          load_balancer: lb.label
        },
        status: 'running',
        event_code: '3aa2d4d297b9b59c'
      )
      event.load_balancers << lb

      is_valid = LetsEncryptServices::ValidateDomainService.new(lb, event).perform

      # Intentionally skipping validations/callbacks to avoid existing schema issues.
      lb.update_columns(
        domain_valid: is_valid,
        domain_valid_check: Time.now
      )
      is_valid ? event.done! : event.fail!('Fatal Error')
      if is_valid && lb.le
        le_gen_service = LoadBalancerServices::LetsEncryptService.new(lb, audit)
        le_gen_service.event = event
        le_gen_service.perform
      end
      is_valid
    end
  rescue => e
    ExceptionAlertService.new(e, '1562c86f46a4fd4a').perform
    if defined?(event) && event
      event.event_details.create!(data: e.message, event_code: '1562c86f46a4fd4a')
      event.fail! 'Fatal Error'
    end
  end
end
