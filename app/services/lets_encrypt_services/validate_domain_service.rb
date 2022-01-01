module LetsEncryptServices
  ##
  # Validate Domain Name for Lets Encrypt
  class ValidateDomainService

    attr_accessor :domain,
                  :event,
                  :load_balancer,
                  :container_domain

    def initialize(obj, event)
      if obj.is_a?(Deployment::ContainerDomain)
        self.container_domain = obj
        self.domain = obj.domain
        self.load_balancer = nil
      elsif obj.is_a?(LoadBalancer)
        self.load_balancer = obj
        self.container_domain = nil
        self.domain = obj.domain
      else
        self.domain = nil
        self.load_balancer = nil
        self.container_domain = nil
      end
      self.event = event
      @dns = Dnsruby::Resolver.new( { nameserver: NS_LIST, port: Rails.env.test? ? 25353 : 53 } )
      @dns.retry_delay = 1
      @dns.retry_times = 3
    end

    # @return [Boolean]
    def perform
      is_valid = valid_ip?
      is_valid = false unless valid_caa?
      is_valid = false unless valid_http?
      is_valid ? event.done! : event.fail!("Invalid Domain Configuration")
      is_valid
    rescue SocketError => e
      event.event_details.create!(
        data: "Domain Error: #{e.message}",
        event_code: 'c7fb07ab86991059'
      )
      event.fail! 'Domain Error'
      false
    rescue => e
      ExceptionAlertService.new(e, '77fd80bc5d8a29a1').perform
      event.event_details.create!(
        data: "Fatal Error: #{e.message}",
        event_code: 'a1d62edbd48dc8f1'
      )
      event.fail! 'Fatal Error'
      false
    end

    private

    ##
    # Ensure that there are no redirects in place that would prevent the domain
    # from being properly validated.
    def valid_http?
      return true if Rails.env.test? # No good to test this right now...
      return true if load_balancer # Not performing this check on load balancer domains right now.
      response = HTTParty.get("https://#{domain}/.well-known/acme-challenge/http_check", verify: false, follow_redirects: false)
      unless response.code == 200
        event.event_details.create!(
          data: "Invalid domain configuration: Unable to connect to validation url. Please ensure there are no redirect rules on '/.well-known/acme-challenge/' URLs.",
          event_code: '259530068a4122cc'
        )
        return false
      end
      true
    rescue => e
      event.event_details.create!(
        data: "Fatal Error: #{e.message}",
        event_code: '0962b58462491cb2'
      )
      event.fail! 'Fatal Error'
      false
    end

    def valid_ip?
      dns_resource, dns_resource_six = load_a_records!

      if (dns_resource + dns_resource_six).empty?
        event.event_details.create!(
          data: "Missing DNS records for #{domain}.",
          event_code: 'afda9ae32934c1d8'
        )
        return false
      end

      is_valid = true
      (dns_resource + dns_resource_six).each do |resource|
        break unless is_valid
        is_valid = if load_balancer
          load_balancer.ip_allowed? resource
        else
          container_domain.le_dns_allowed? resource
        end
        event.event_details.create!(data: "Invalid DNS resource found: #{resource}", event_code: '510806d5621c97d5') unless is_valid
      end

      if load_balancer
        dns_resource_wildcard = load_wildcard_cname!
        if dns_resource_wildcard.nil?
          event.event_details.create!(
            data: "Missing CNAME record. Expected *.#{domain} to point to #{domain}.",
            event_code: '2721edc59787a807'
          )
          is_valid = false
        elsif dns_resource_wildcard.name.to_s != domain
          event.event_details.create!(
            data: "Invalid CNAME record. Expected *.#{domain} to point to #{domain}, instead we found #{dns_resource_wildcard.name.to_s}.",
            event_code: '635285f7f2889009'
          )
          is_valid = false
        end
      end

      is_valid
    end

    ##
    # Determine if the CAA records for this domain will permit a LetsEncrypt certificate to be issued
    #
    # Resources:
    # - [DNSimple Wiki](https://support.dnsimple.com/articles/caa-record/)
    # - [LetsEncrypt CAA](https://letsencrypt.org/docs/caa/)
    #
    # @return [Boolean]
    def valid_caa?
      full_domain = domain
      root_tld = DomainPrefix.registered_domain full_domain

      if root_tld.nil? # We should always have a valid TLD!
        event.event_details.create!( data: "Invalid TLD: #{full_domain}.", event_code: '1a6505df079a9b3c' )
        Raven.capture_message("Root TLD error: #{full_domain} - #{ENV['APP_ID']}")
        return false
      end

      # loop through each subdomain moving up towards the TLD. Start with the original domain and work up.
      # When the first CAA record is found, that is the one we will use as it will have priority over the higher ones.
      domains = []
      full_domain.gsub(".#{root_tld}",'').split('.').each do |i|
        break if full_domain == root_tld # Stop when we hit the root domain.
        domains << full_domain
        full_domain = full_domain.split("#{i}.")[1] # Remove subdomain from `full_domain` and continue loop.
      end
      domains << root_tld

      # user domain domains:
      # - should have an empty set, or
      # - should have an `issue "letsencrypt.org"` record
      # - In prep for `cansignhttpexchanges` also allow: `issue "letsencrypt.org; cansignhttpexchanges=yes"`
      is_valid = true
      domains.each do |d|
        # PowerDNS will return a CNAME if one exists, so we need to filter that out.
        begin
          response = @dns.query(d, 'CAA').answer.select { |i| i.is_a?(Dnsruby::RR::IN::CAA) }
        rescue Dnsruby::NXDomain
          if d == full_domain
            event.event_details.create!(
              data: "Error! #{d} does not exist!",
              event_code: 'c818dccc04f6889b'
            )
            is_valid = false
            break
          end
          next
        rescue Dnsruby::Refused => e
          ExceptionAlertService.new(e, 'afb5d727910b5954').perform
          if d == full_domain
            event.event_details.create!(
              data: "Error! #{d} does not exist!",
              event_code: 'afb5d727910b5954'
            )
            is_valid = false
            break
          end
          next
        end
        next if response.empty?
        invalid_records = []
        invalid_wild_records = []
        le_caa_exists = false
        le_wildcard_caa_exists = false
        response.each do |i|
          val_check = i.property_value.split(';')[0]&.strip
          if i.property_tag == 'issue' && val_check == 'letsencrypt.org'
            le_caa_exists = true
          elsif i.property_tag == 'issuewild' && val_check == 'letsencrypt.org'
            le_wildcard_caa_exists = true
          elsif i.property_tag == 'issue'
            invalid_records << "#{i.property_tag} #{i.property_value}"
          elsif i.property_tag == 'issuewild'
            invalid_wild_records << "#{i.property_tag} #{i.property_value}"
          end
        end
        # We're checking from left-to-right, and so the first valid CAA record we find will work.
        if load_balancer && (le_caa_exists && le_wildcard_caa_exists)
          is_valid = true
          break
        elsif !load_balancer && le_caa_exists
          is_valid = true
          break
        end

        ##
        # If we made it this far, then we know we had CAA records. Therefore, this must exist.
        if !le_caa_exists && invalid_records.empty?
          event.event_details.create!(
            data: "CAA record found on #{d}, but missing LetsEncrypt. Please add: 0 issue \"letsencrypt.org\".\nLearn more about CAA records and LetsEncrypt: https://letsencrypt.org/docs/caa/.",
            event_code: '87744f149e2ed5ad'
          )
        elsif !le_caa_exists
          event.event_details.create!(
            data: "CAA record found on #{d}, but missing LetsEncrypt. Please add: 0 issue \"letsencrypt.org\".\nLearn more about CAA records and LetsEncrypt: https://letsencrypt.org/docs/caa/.\n\n\nInvalid Records:\n\n#{invalid_records.join("\n")}",
            event_code: '87744f149e2ed5ad'
          )
        end

        # if we have ANY CAA records, we MUST also have a wildcard record.
        if !le_wildcard_caa_exists && load_balancer
          if invalid_wild_records.empty?
            event.event_details.create!(
              data: "CAA record found on #{d}, but missing LetsEncrypt. Please add: 0 issuewild \"letsencrypt.org\".\nLearn more about CAA records and LetsEncrypt: https://letsencrypt.org/docs/caa/.",
              event_code: '47f76d011a0cc587'
            )
          else
            event.event_details.create!(
              data: "CAA record found on #{d}, but missing LetsEncrypt. Please add: 0 issuewild \"letsencrypt.org\".\nLearn more about CAA records and LetsEncrypt: https://letsencrypt.org/docs/caa/.\n\nInvalid Records:\n\n#{invalid_wild_records.join("\n")}",
              event_code: '47f76d011a0cc587'
            )
          end
        end

        ##
        # If we made it this far, then we have a subdomain with an invalid CAA record. Halt!
        is_valid = false
        break
      end
      is_valid
    end

    def load_a_records!
      dns_resource = @dns.query(domain, 'A').answer.select { |i| i.is_a?(Dnsruby::RR::IN::A) }.map { |i| IPAddr.new(i.address.to_s) }
      dns_resource_six = @dns.query(domain, 'AAAA').answer.select { |i| i.is_a?(Dnsruby::RR::IN::AAAA) }.map { |i| IPAddr.new(i.address.to_s) }
      return dns_resource, dns_resource_six
    rescue Dnsruby::NXDomain
      return [],[]
    rescue Dnsruby::Refused => e
      ExceptionAlertService.new(e, 'bf4c286afe9ba40e').perform
      event.event_details.create!(
        data: "Error! #{domain} does not exist!",
        event_code: 'afb5d727910b5954'
      )
      return [],[]
    end

    def load_wildcard_cname!
      dns = if Rails.env.test?
              Resolv::DNS.new(nameserver_port: [['localhost', 25353]])
            else
              Resolv::DNS.new(nameserver: NS_LIST)
            end
      dns.timeouts = Rails.env.test? ? 30 : 5
      dns_resource_wildcard = dns.getresource("#{SecureRandom.hex(8)}.#{domain}", Resolv::DNS::Resource::IN::CNAME)
    rescue Resolv::ResolvError # Record does not exist.
      nil
    end

  end
end
