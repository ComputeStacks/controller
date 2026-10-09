require "test_helper"

class LetsEncryptAuthTest < ActiveSupport::TestCase
  setup do
    @lb = load_balancers(:default)
    account = LetsEncryptAccount.create!(email: "test@example.com")
    @cert = LetsEncrypt.create!(account: account)
    @lb.update_columns(le: true, lets_encrypt_id: @cert.id)
  end

  def set_alias_zone(value)
    Setting.le_dns_alias_zone # find-or-create
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: value)
  end

  def auth_for(domain)
    LetsEncryptAuth.create!(
      certificate: @cert,
      domain: domain,
      challenge_type: "dns",
      record_name: "_acme-challenge",
      record_type: "TXT",
      record_content: "abc"
    )
  end

  test "load balancer is found by domain" do
    assert_equal @lb, auth_for(@lb.domain).load_balancer
    assert_nil auth_for("other.example.com").load_balancer
  end

  test "local zone: unchanged behavior" do
    set_alias_zone("acme.example.com")
    @lb.update_columns(domain: "apps.foo.local")
    auth = auth_for("apps.foo.local")
    assert_equal dns_zones(:user_zone), auth.dns_zone
    assert_nil auth.dns_alias
    assert_equal "_acme-challenge.apps.foo.local", auth.dns_record_fqdn
  end

  test "alias: falls back to the alias zone" do
    alias_zone = Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    set_alias_zone("acme.bar.local")
    auth = auth_for(@lb.domain)
    assert_equal "lb#{@lb.id}.acme.bar.local", auth.dns_alias
    assert_equal alias_zone, auth.dns_zone
    assert_equal "lb#{@lb.id}.acme.bar.local", auth.dns_record_fqdn
  end

  test "alias: exact alias zone wins over a local parent zone" do
    # foo.local is a local zone (fixture); acme.foo.local is delegated to us.
    alias_zone = Dns::Zone.create!(name: "acme.foo.local", skip_provision_driver: true)
    set_alias_zone("acme.foo.local")
    auth = auth_for(@lb.domain)
    assert_equal alias_zone, auth.dns_zone
    assert_equal "lb#{@lb.id}.acme.foo.local", auth.dns_record_fqdn
  end

  test "alias configured but the alias zone does not exist" do
    set_alias_zone("acme.missing.local")
    auth = auth_for(@lb.domain)
    assert_equal "lb#{@lb.id}.acme.missing.local", auth.dns_alias
    assert_nil auth.dns_zone
  end

  test "neither a local zone nor an alias" do
    auth = auth_for(@lb.domain)
    assert_nil auth.dns_alias
    assert_nil auth.dns_zone
    assert_equal "_acme-challenge.#{@lb.domain}", auth.dns_record_fqdn
  end

  test "no alias when the domain has no load balancer" do
    set_alias_zone("acme.example.com")
    auth = auth_for("unrelated.example.com")
    assert_nil auth.dns_alias
    assert_nil auth.dns_zone
  end
end
