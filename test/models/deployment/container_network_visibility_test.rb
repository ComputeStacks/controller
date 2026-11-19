require "test_helper"
require "minitest/mock"

class Deployment::ContainerNetworkVisibilityTest < ActiveSupport::TestCase
  setup do
    @container = deployment_containers(:wordpress_1)
    @event = EventLog.create!(
      locale: "container.provision",
      event_code: "9c0e4b7a1f3d2856",
      status: "running"
    )
  end

  # It used to answer the `users <<` array, which reads as success.
  test "set_ip_address! returns false when there is no network" do
    Network.where(deployment_id: @container.deployment.id).update_all(deployment_id: nil)
    @container.ip_address.destroy!
    @container.reload

    assert_equal false, @container.set_ip_address!
  end

  test "runtime_config_blocker names the missing private IP" do
    @container.ip_address.destroy!
    @container.reload

    assert_equal "no private IP address", @container.runtime_config_blocker
  end

  test "runtime_config_blocker is nil when the cheap checks pass" do
    assert_nil @container.runtime_config_blocker
  end

  test "build! says why when there is no runtime config" do
    @container.ip_address.destroy!
    @container.reload

    Docker::Container.stub(:create, ->(*) { flunk "must not create" }) do
      assert_equal false, @container.build!(@event)
    end

    detail = @event.event_details.find_by(event_code: "c84556a62f63c3b1")
    assert_match(/#{@container.name}: no private IP address\./, detail.data)
  end

  test "build! falls back to a generic reason when the cheap checks pass" do
    @container.stub(:runtime_config, nil) do
      assert_equal false, @container.build!(@event)
    end

    assert_match(/custom host setup failed or runtime config raised/, @event.event_details.find_by(event_code: "c84556a62f63c3b1").data)
  end

  test "build! on an SFTP container says why too" do
    sftp = deployment_sftp(:project_test_testone)
    sftp.ip_address.destroy!
    sftp.reload

    assert_equal false, sftp.build!(@event)
    assert_match(/no private IP address/, @event.event_details.find_by(event_code: "c84556a62f63c3b1").data)
  end
end
