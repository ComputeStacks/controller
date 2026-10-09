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
end
