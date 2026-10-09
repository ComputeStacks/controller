require "test_helper"

class LoadBalancerAcmeDnsAliasTest < ActiveSupport::TestCase
  setup do
    @lb = load_balancers(:default)
    @lb.update_columns(le: true)
  end

  def set_alias_zone(value)
    Setting.le_dns_alias_zone # find-or-create
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: value)
  end

  test "setting is blank by default" do
    assert_nil Setting.le_dns_alias_zone
    assert Setting.exists?(name: "le_dns_alias_zone", category: "acme")
  end

  test "setting is normalized" do
    set_alias_zone("  ACME.Example.COM. ")
    assert_equal "acme.example.com", Setting.le_dns_alias_zone
    set_alias_zone("   ")
    assert_nil Setting.le_dns_alias_zone
  end

  test "no alias when the setting is blank" do
    assert_nil @lb.acme_dns_alias
    refute @lb.acme_dns_alias_required?
  end

  test "alias is derived from the id" do
    set_alias_zone("acme.example.com")
    assert_equal "lb#{@lb.id}.acme.example.com", @lb.acme_dns_alias
  end

  test "no alias for an unsaved load balancer" do
    set_alias_zone("acme.example.com")
    assert_nil LoadBalancer.new(domain: "x.example.com").acme_dns_alias
  end

  test "alias required when no local zone covers the domain" do
    set_alias_zone("acme.example.com")
    assert @lb.acme_dns_alias_required?
  end

  test "alias not required when a local zone covers the domain" do
    set_alias_zone("acme.example.com")
    @lb.update_columns(domain: "apps.foo.local")
    refute @lb.acme_dns_alias_required?
  end

  test "alias not required when automatic certificates are off" do
    set_alias_zone("acme.example.com")
    @lb.update_columns(le: false)
    refute @lb.acme_dns_alias_required?
  end
end
