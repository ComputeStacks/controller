require "test_helper"

class SettingTest < ActiveSupport::TestCase
  BASTION_V2 = "ghcr.io/computestacks/cs-docker-bastion:v2"
  BASTION_V4 = "ghcr.io/computestacks/cs-docker-bastion:v4"

  def bastion_setting
    Setting.find_by(name: "cs_bastion_image", category: "computestacks")
  end

  def migrate_bastion_image
    require Rails.root.join("db/migrate/20261009000001_update_stock_bastion_image.rb").to_s
    ActiveRecord::Migration.suppress_messages { UpdateStockBastionImage.new.migrate(:up) }
    bastion_setting.reload.value
  end

  test "the bastion image defaults to v4" do
    bastion_setting&.destroy
    assert_equal BASTION_V4, Setting.computestacks_bastion_image
  end

  test "the migration moves the stock v2 bastion image to v4" do
    Setting.computestacks_bastion_image
    bastion_setting.update!(value: BASTION_V2)
    assert_equal BASTION_V4, migrate_bastion_image
  end

  test "the migration leaves an operator's bastion image alone" do
    Setting.computestacks_bastion_image
    custom = "registry.example.com/ops/bastion:v2"
    bastion_setting.update!(value: custom)
    assert_equal custom, migrate_bastion_image
  end

  test "parse_provider_env handles comments, blanks, equals signs and empty values" do
    text = "# creds\n\nAPI_TOKEN=abc=def==\n  OTHER = spaced \nEMPTY=\n"
    assert_equal({"API_TOKEN" => "abc=def==", "OTHER" => "spaced", "EMPTY" => ""}, Setting.parse_provider_env(text))
    assert_equal({}, Setting.parse_provider_env(nil))
  end

  test "parse_provider_env rejects bad input naming the line number only" do
    {
      "OK=1\nlower=secretvalue1" => 2,
      "OK=1\nPATH=/tmp" => 2,
      "A=secretvalue1\nA=secretvalue2" => 2,
      "OK=1\nnoequalssecretvalue1" => 2,
      "1BAD=secretvalue1" => 1
    }.each do |text, line|
      e = assert_raises(ArgumentError, text) { Setting.parse_provider_env(text) }
      assert_includes e.message, "Line #{line}"
      refute_match(/secretvalue|noequals/, e.message)
    end
  end

  test "parse_provider_env rejects the propagation check bypass only in production" do
    text = "CERT_ISSUER_INSECURE_SKIP_PROPAGATION_CHECK=1"
    assert_equal({"CERT_ISSUER_INSECURE_SKIP_PROPAGATION_CHECK" => "1"}, Setting.parse_provider_env(text))
    original = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::EnvironmentInquirer.new("production") }
    begin
      assert_raises(ArgumentError) { Setting.parse_provider_env(text) }
    ensure
      Rails.define_singleton_method(:env, original)
    end
  end

  test "le_dns_provider validates its code on save" do
    Setting.le_dns_provider
    s = Setting.find_by!(name: "le_dns_provider")
    assert s.update(value: "cloudflare")
    assert s.update(value: "")
    refute s.update(value: "Bad Code!")
    assert s.errors[:value].any?
  end

  test "le_dns_provider_secret validates on save and round-trips encrypted" do
    Setting.le_dns_provider_secret
    s = Setting.find_by!(name: "le_dns_provider_secret")
    refute s.update(value: "nonsense-secret-line")
    refute_includes s.errors.full_messages.join, "nonsense-secret-line"
    assert s.update(value: "TOKEN=abc\nOTHER=x=y")
    refute_includes s.reload.value, "TOKEN"
    assert_equal({"TOKEN" => "abc", "OTHER" => "x=y"}, Setting.le_dns_provider_env)
  end
end
