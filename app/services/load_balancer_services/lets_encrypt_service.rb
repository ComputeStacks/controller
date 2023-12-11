module LoadBalancerServices
  # Generate a wildcard LetsEncrypt for this load balancer
  #
  # If the load balanxcer's domain is not validated, this will hault and trigger that, which will in turn trigger this again.
  #
  # @!attribute load_balancer
  #   @return [LoadBalancer]
  # @!attribute event
  #   @return [Event]
  # @!attribute errors
  #   @return [Array]
  class LetsEncryptService

    attr_accessor :load_balancer,
                  :audit,
                  :event,
                  :errors

    # @param load_balancer [LoadBalancer]
    # @param audit [Audit]
    def initialize(load_balancer, audit = nil)
      self.load_balancer = load_balancer
      self.audit = audit
      self.event = nil
      self.errors = []
    end

    # @return [Boolean]
    def perform
      # Immediately halt if we're disable LE and there is no active cert.
      if load_balancer.lets_encrypt.nil? && !load_balancer.le
        errors << "Disabling lets encrypt."
        return false
      end
      generate_audit! if audit.nil?
      unless valid?
        event.update(status: 'failed') if event
        return false
      end

      lecert = load_balancer.lets_encrypt
      lecert = LetsEncrypt.create!(user_id: nil, account: LetsEncryptAccount.find_or_create) if lecert.nil?

      if lecert.nil?
        self.errors << "Failed to create LetsEncrypt"
        event.event_details.create!(data: "Failed to create LetsEncrypt", event_code: '2cc0021dbec795aa')
        event.fail! 'Failure'
      else
        load_balancer.update lets_encrypt: lecert
        LetsEncryptWorkers::GenerateCertWorker.perform_async lecert.id, event.id
      end
      errors.empty?
    end

    private

    def valid?
      generate_event! if event.nil?
      unless load_balancer.domain_valid
        LoadBalancerWorkers::ValidateDomainWorker.perform_async load_balancer.id, audit.id
        event.cancel! 'Domain not valid' if event
        return false
      end
      # If we have a cert, and we're disabling, remove and reload.
      if load_balancer.lets_encrypt && !load_balancer.le
        le = load_balancer.lets_encrypt
        load_balancer.update lets_encrypt: nil
        LetsEncryptWorkers::GenerateCertWorker.perform_async le.id, event.id
        errors << "Disabling lets encrypt."
        return false
      end
      if load_balancer.domain.blank?
        self.errors << "Load Balancer does not have a domain name."
      end
      unless load_balancer.domain_valid
        self.errors << "Domain has not yet been validated, unable to proceed."
      end
      event.event_details.create!(data: errors.join(' '), event_code: 'ea9555238abe1f26') unless errors.empty?
      errors.empty?
    end

    # Initialize an audit object if we have none
    def generate_audit!
      return nil if load_balancer.nil?
      self.audit = Audit.create_from_object!(load_balancer, 'updated', '127.0.0.1')
    end

    def generate_event!
      return if event
      self.event = EventLog.create!(
        locale: 'load_balancers.generate_lets_encrypt',
        locale_keys: {
          load_balancer: load_balancer.label
        },
        status: 'running',
        audit: audit,
        event_code: 'f68bcf5786036bf2'
      )
      self.event.load_balancers << load_balancer
    end

  end
end
