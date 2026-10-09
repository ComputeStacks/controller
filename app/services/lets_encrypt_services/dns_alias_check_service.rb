module LetsEncryptServices
  ##
  # Verify that a load balancer's domain delegates its ACME DNS-01 challenge
  # to our DNS alias zone, i.e. that this record exists at the operator's DNS host:
  #
  #   _acme-challenge.<domain>. CNAME lb<id>.<alias zone>.
  #
  # The CNAME target must match exactly. Presence alone is not enough: the
  # required `*.<domain> CNAME <domain>` wildcard synthesizes
  # `_acme-challenge.<domain> CNAME <domain>` when the explicit record is missing.
  #
  #   svc = LetsEncryptServices::DnsAliasCheckService.new(load_balancer)
  #   svc.perform # => true / false
  #   svc.errors  # => ["..."]
  #   svc.failure # => nil, :no_alias, :missing_zone, :missing_record, :mismatch, :lookup_error
  #
  class DnsAliasCheckService
    attr_reader :load_balancer, :errors, :failure

    # @param load_balancer [LoadBalancer]
    # @param resolver [Dnsruby::Resolver, nil] injectable for tests
    def initialize(load_balancer, resolver: nil)
      @load_balancer = load_balancer
      @errors = []
      @dns = resolver || Dnsruby::Resolver.new({
        nameserver: NS_LIST,
        port: NS_PORT,
        do_caching: false,
        retry_delay: 1,
        retry_times: 3
      })
    end

    # @return [Boolean]
    def perform
      @errors = []
      @failure = nil
      expected = load_balancer.acme_dns_alias
      if expected.blank?
        errors << "No DNS alias zone is configured (setting 'le_dns_alias_zone'), so #{domain} cannot use DNS alias validation."
        @failure = :no_alias
        return false
      end

      # Exact name, not Dns::Zone.find_covering: a suffix walk returns the
      # shortest match, so with `acme.example.com` delegated to us and
      # `example.com` also local, it would pick the parent zone, below the
      # delegation cut, where ACME would never see the challenge record.
      alias_zone = Setting.le_dns_alias_zone
      if Dns::Zone.find_by(name: alias_zone).nil?
        errors << "The DNS alias zone #{alias_zone} does not exist as a DNS zone in ComputeStacks. Create it (it must be delegated to our DNS servers) before using DNS alias validation."
        @failure = :missing_zone
        return false
      end

      found = lookup_cname
      if found == :error
        @failure = :lookup_error
        return false
      end

      if found.nil?
        errors << "Missing DNS alias record. Since #{domain} is not hosted on our DNS, please add this record at your DNS provider: #{required_record(expected)}"
        @failure = :missing_record
        return false
      end

      unless found == expected
        errors << "Invalid DNS alias record. Expected #{challenge_name} to be a CNAME to #{expected}, instead we found #{found}. Please add this record at your DNS provider: #{required_record(expected)}"
        @failure = :mismatch
        return false
      end

      true
    end

    private

    def domain
      load_balancer.domain.to_s.strip.downcase.delete_suffix(".")
    end

    def challenge_name
      "_acme-challenge.#{domain}"
    end

    def required_record(expected)
      "#{challenge_name}. CNAME #{expected}."
    end

    def normalize(name)
      name.to_s.strip.downcase.delete_suffix(".")
    end

    # @return [String, nil, Symbol] normalized CNAME target, nil when absent, :error on lookup failure
    def lookup_cname
      answer = @dns.query(challenge_name, "CNAME").answer
      cname = answer.find do |rr|
        rr.is_a?(Dnsruby::RR::IN::CNAME) && normalize(rr.name) == challenge_name
      end
      cname.nil? ? nil : normalize(cname.rdata)
    rescue Dnsruby::NXDomain
      nil
    rescue Dnsruby::Refused
      errors << "DNS lookup of #{challenge_name} was refused. Please ensure #{domain} exists and add this record at your DNS provider: #{required_record(load_balancer.acme_dns_alias)}"
      :error
    rescue Dnsruby::ResolvTimeout, Dnsruby::ResolvError => e
      errors << "DNS lookup of #{challenge_name} failed (#{e.class.name.demodulize}: #{e.message}). Expected this record: #{required_record(load_balancer.acme_dns_alias)}"
      :error
    end
  end
end
