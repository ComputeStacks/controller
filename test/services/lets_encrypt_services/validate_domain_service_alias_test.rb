require "test_helper"

class LetsEncryptServices::ValidateDomainServiceAliasTest < ActiveSupport::TestCase
  class FakeResolver
    Answer = Struct.new(:answer)

    def initialize(records)
      @records = records
    end

    # Any unlisted subdomain of `wildcard_suffix` resolves through the wildcard CNAME.
    def query(name, type)
      r = @records.fetch([name, type]) do
        name.end_with?(@records[:wildcard_suffix]) ? @records[[:wildcard, type]] : nil
      end
      raise r if r.is_a?(Class)
      Answer.new(Array(r).map { |rr| Dnsruby::RR.create(rr.gsub("{name}", name)) })
    end
  end

  setup do
    @lb = load_balancers(:default)
    @lb.update_columns(le: true, public_ip: "198.51.100.10")
    Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    Setting.le_dns_alias_zone
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: "acme.bar.local")
    @domain = @lb.domain
    @alias = "lb#{@lb.id}.acme.bar.local"
    @qname = "_acme-challenge.#{@domain}"
  end

  def run_validation(acme_record)
    records = {
      [@domain, "A"] => ["#{@domain}. 300 IN A 198.51.100.10"],
      [@domain, "AAAA"] => [],
      :wildcard_suffix => ".#{@domain}",
      # No trailing dot, matching what the existing wildcard check expects from Dnsruby.
      [:wildcard, "CNAME"] => ["{name}. 300 IN CNAME #{@domain}"]
    }
    records[[@qname, "CNAME"]] = acme_record unless acme_record.nil?
    event = EventLog.create!(locale: "load_balancers.validate_domain", event_code: "0000000000000000", status: "running")
    svc = LetsEncryptServices::ValidateDomainService.new(@lb, event)
    svc.instance_variable_set(:@dns, FakeResolver.new(records))
    [svc.perform, event.reload]
  end

  test "valid with the correct alias CNAME" do
    ok, event = run_validation(["#{@qname}. 300 IN CNAME #{@alias}."])
    assert ok, event.event_details.pluck(:data).join("\n")
  end

  test "invalid when only the wildcard-synthesized CNAME exists" do
    ok, event = run_validation(nil)
    refute ok
    assert event.event_details.where(event_code: "262b44b752382307").exists?
  end

  test "invalid when the challenge name does not exist" do
    ok, event = run_validation(Dnsruby::NXDomain)
    refute ok
    assert event.event_details.where(event_code: "076f360f9c009c74").exists?
  end

  test "alias check skipped when a local zone covers the domain" do
    @lb.update_columns(domain: "apps.foo.local")
    @domain = "apps.foo.local"
    @qname = "_acme-challenge.#{@domain}"
    ok, event = run_validation(nil)
    assert ok, event.event_details.pluck(:data).join("\n")
  end
end
