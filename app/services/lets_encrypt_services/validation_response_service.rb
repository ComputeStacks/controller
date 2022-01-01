module LetsEncryptServices
  ##
  # Process and handle a validation response from LetsEncrypt,
  # and perform specific actions based on the kind of response.
  #
  # List of [LetsEncrypt Status Types](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#errors)
  #
  # Example data from LetsEncrypt
  #        {
  #          "type" => "urn:ietf:params:acme:error:connection",
  #          "detail" => "Fetching http://www.example.com/.well-known/acme-challenge/#UDKVL6DjdFE7oPVfVUd5RV-LRH5huqO_mBTusMU7iRY: Connection reset by peer",
  #          "status" => 400
  #        }
  #
  #
  # @!attribute container_domain
  #   @return [Deployment::Containerdomain]
  # @!attribute domain
  #   @return [String] raw domain
  # @!attribute event
  #   @return [EventLog]
  # @!attribute type
  #   @return [String] Type of LE validation
  # @!attribute detail
  #   @return [String] details of error
  class ValidationResponseService

    attr_accessor :container_domain,
                  :domain,
                  :event,
                  :type,
                  :detail

    # @param container_domain [Deployment::ContainerDomain]
    # @param raw_domain [String] raw domain
    # @param data [Hash]
    # @param event [EventLog]
    def initialize(container_domain, raw_domain, data, event)
      self.container_domain = container_domain
      self.domain = raw_domain
      self.event = event
      if data.kind_of? Hash
        self.type = data['type'].gsub('urn:ietf:params:acme:error:','').strip
        self.detail = data['detail']
      else
        self.type = nil
        self.detail = nil
      end
    end

    # Process based on LetsEncrypt `type`.
    # @return [Boolean]
    def perform
      return unless valid?
      case type
      when 'caa'
        event.event_details.create!(
          data: "Error! You have a CAA record on your domain that is preventing us from ",
          event_code: '57893ea2173caee1'
        )
        cancel_domain_validation!
      when 'connection', 'malformed', 'incorrectResponse', 'serverInternal', 'tls'
        event.event_details.create!(
          data: "There was a problem with LetsEncrypt connecting to our system, we will retry your certificate.\n\nError: #{detail}",
          event_code: 'c920c292f048dccd'
        )
        cancel_domain_validation!
        schedule_new_validation!
      when 'dns'
        event.event_details.create!(
          data: "There was a problem connecting to your DNS server, please verify your NS records are correct.",
          event_code: 'f8e636b30384111b'
        )
        schedule_new_validation!
      when 'rateLimited'
        event.event_details.create!(
          data: "We are temporarily rate limited by LetsEncrypt, we will attempt to renew your certificate later",
          event_code: '972b196893bfdf09'
        )
        false
      when 'rejectedIdentifier'
        event.event_details.create!(
          data: "LetsEncrypt has rejected this domain for issuance.\n\nError: #{detail}",
          event_code: '5e772aabba86d0c1'
        )
        cancel_domain_validation!
      else
        event.event_details.create!(
          data: "Validation Failed for #{domain}.\n\ntype: #{type}\ndetail: #{detail}",
          event_code: '9dec84a9854b0932'
        )
        cancel_domain_validation!
      end
    end

    private

    def cancel_domain_validation!
      container_domain.update(le_ready: false, le_ready_checked: Time.now)
    end

    def schedule_new_validation!
      LetsEncryptWorkers::ValidateDomainWorker.perform_async container_domain.id
    end

    # @return [Boolean]
    def valid?
      process_raw_event! if container_domain.nil?
      return false if container_domain.nil?
      return false if domain.blank?
      return false if event.nil?
      true
    end

    # For situations where ContainerDomain is nil, just record the data and thats it.
    def process_raw_event!
      event.event_details.create!(
        data: "Validation Failed for #{domain}.\n\ntype: #{type}\ndetail: #{detail}",
        event_code: '307dac0a2815fe1c'
      )
    end

  end
end
