require "test_helper"
require "minitest/mock" # not loaded by the project's test_helper; needed for Object#stub

class ContainerService::SettingConfigTest < ActiveSupport::TestCase
  setup do
    @setting = container_service_setting_configs(:wordpress_2)
    @deployment = @setting.container_service.deployment
  end

  test "param_type is restricted to static and password" do
    @setting.param_type = "bogus"
    refute @setting.valid?
    refute @setting.errors[:param_type].empty?

    %w[static password].each do |type|
      @setting.param_type = type
      assert @setting.valid?, "#{type} should be a valid param_type"
    end
  end

  ##
  # The destroy hook is the whole reason deleting a setting is safe: without it the
  # published blob keeps describing a setting that no longer exists, and nothing else
  # republishes it on a normal running project. A revert would otherwise be silent.
  #
  # Asserted by stubbing the worker rather than by counting Sidekiq's fake queue. The
  # worker is `lock: :until_executed, on_conflict: :reject`, and under
  # `Sidekiq::Testing.fake!` nothing ever executes, so the unique lock taken by an
  # earlier test in the same process is never released and this enqueue is discarded as
  # a duplicate. That is correct production behaviour (it is what collapses a burst of
  # refreshes into one) but it makes a queue-size assertion measure Redis state left
  # over from other tests instead of this callback.
  test "destroying a setting republishes the project metadata" do
    refreshed = []
    ProjectWorkers::RefreshMetadataWorker.stub(:perform_async, ->(id) { refreshed << id }) do
      assert @setting.destroy
    end
    assert_equal [@deployment.id], refreshed
  end

  test "skip_metadata_refresh suppresses the destroy refresh" do
    refreshed = []
    ProjectWorkers::RefreshMetadataWorker.stub(:perform_async, ->(id) { refreshed << id }) do
      @setting.skip_metadata_refresh = true
      assert @setting.destroy
    end
    assert_empty refreshed
  end
end
