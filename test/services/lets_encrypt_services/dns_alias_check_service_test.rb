require "test_helper"

class LetsEncryptServices::DnsAliasCheckServiceTest < ActiveSupport::TestCase
  # Minimal stand-in for Dnsruby::Resolver. `records` maps [name, type] to an
  # array of RR strings, or to an exception class to raise.
  class FakeResolver
    Answer = Struct.new(:answer)

    def initialize(records)
      @records = records
    end

    def query(name, type)
      r = @records[[name, type]]
      raise r if r.is_a?(Class)
      Answer.new(Array(r).map { |rr| Dnsruby::RR.create(rr) })
    end
  end

  setup do
    @lb = load_balancers(:default)
    @lb.update_columns(le: true)
    Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    Setting.le_dns_alias_zone
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: "acme.bar.local")
    @alias = "lb#{@lb.id}.acme.bar.local"
    @qname = "_acme-challenge.#{@lb.domain}"
  end

  def check(records)
    svc = LetsEncryptServices::DnsAliasCheckService.new(@lb, resolver: FakeResolver.new(records))
    [svc.perform, svc]
  end

  test "correct CNAME passes" do
    ok, svc = check({[@qname, "CNAME"] => ["#{@qname}. 300 IN CNAME #{@alias.upcase}."]})
    assert ok
    assert_empty svc.errors
    assert_nil svc.failure
  end

  test "wildcard-synthesized CNAME to the domain fails" do
    ok, svc = check({[@qname, "CNAME"] => ["#{@qname}. 300 IN CNAME #{@lb.domain}."]})
    refute ok
    assert_equal :mismatch, svc.failure
    assert_includes svc.errors.join, "#{@qname}. CNAME #{@alias}."
  end

  test "NXDomain fails with the record to add" do
    ok, svc = check({[@qname, "CNAME"] => Dnsruby::NXDomain})
    refute ok
    assert_equal :missing_record, svc.failure
    assert_includes svc.errors.join, "#{@qname}. CNAME #{@alias}."
  end

  test "empty answer fails" do
    ok, svc = check({})
    refute ok
    assert_equal :missing_record, svc.failure
  end

  test "refused and timeouts fail" do
    ok, svc = check({[@qname, "CNAME"] => Dnsruby::Refused})
    refute ok
    assert_equal :lookup_error, svc.failure
    ok, svc = check({[@qname, "CNAME"] => Dnsruby::ResolvTimeout})
    refute ok
    assert_equal :lookup_error, svc.failure
    refute_empty svc.errors
  end

  test "fails when the alias zone is not a local zone" do
    Dns::Zone.find_by(name: "acme.bar.local").destroy
    ok, svc = check({[@qname, "CNAME"] => ["#{@qname}. 300 IN CNAME #{@alias}."]})
    refute ok
    assert_equal :missing_zone, svc.failure
  end

  test "fails when no alias zone is configured" do
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: "")
    ok, svc = check({})
    refute ok
    assert_equal :no_alias, svc.failure
  end
end
