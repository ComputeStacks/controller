require "test_helper"
require "minitest/mock"

class NetworkServices::GenerateProjectNetworkServiceTest < ActiveSupport::TestCase
  setup do
    @region = regions(:regionone)
    @project = deployments(:project_test)
    # The service only allocates when the project has no network yet.
    Network.where(deployment_id: @project.id).update_all(deployment_id: nil)
    @project.reload
    @event = EventLog.create!(
      locale: "order.provision",
      event_code: "0a3af01a3384fa10",
      status: "pending"
    )
    @service = NetworkServices::GenerateProjectNetworkService.new(@event, @region, @project)
  end

  ##
  # The regression this pins.
  #
  # The provisioning call's result used to be discarded and `true` returned unconditionally.
  # ProcessOrderService gates on this value, so a network that never reached the node still
  # reported success: the order carried on, built every container, and each one failed with
  # "failed to set up container networking: network ... not found". One clear failure became
  # a broken project plus a fatal error per container, and the order was never rolled back.
  test "a network that could not be provisioned fails the run" do
    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { FailingProvisioner.new }) do
      assert_equal false, @service.perform
    end
  end

  test "a network that was provisioned succeeds" do
    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { PassingProvisioner.new }) do
      assert_equal true, @service.perform
    end
  end

  # ... and the network is still allocated to the project either way: the row is bound before
  # the node is touched, and releasing it is ProcessOrderService#fail_process!'s job.
  test "the network is allocated to the project before the node is touched" do
    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { FailingProvisioner.new }) do
      @service.perform
    end

    assert_not_nil @project.reload.private_network
  end

  # The `has_one` is cached nil for the whole of an order that has not reloaded the project,
  # so a network bound by another caller in the meantime is invisible through it.
  test "skips when the project already has a network row, even with the has_one cached nil" do
    assert_nil @project.private_network
    networks(:net_gen_0).update_columns(deployment_id: @project.id)

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { flunk "must not provision" }) do
      assert_equal true, @service.perform
    end

    assert @event.event_details.where(event_code: "159f58a91922552b").exists?
    assert_equal [networks(:net_gen_0).id], Network.where(deployment_id: @project.id).pluck(:id)
  end

  test "never claims a row already bound to another deployment" do
    other = deployments(:user_project_test)
    Network.where(deployment_id: other.id).update_all(deployment_id: nil)
    networks(:net_gen_0).update_columns(deployment_id: other.id)
    # Fixture ids are hashed, so compute the lowest free one rather than naming it.
    expected_id = Network.where(parent_network_id: networks(:netone).id).inactive.where(deployment_id: nil).minimum(:id)

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { PassingProvisioner.new }) do
      assert_equal true, @service.perform
    end

    assert_equal other.id, networks(:net_gen_0).reload.deployment_id
    claimed = Network.find_by(deployment_id: @project.id)
    assert_not_equal networks(:net_gen_0).id, claimed.id
    assert_equal expected_id, claimed.id
    assert_equal "net#{@project.token.delete("-")}", claimed.name
  end

  test "fails when every free row is already bound" do
    other = deployments(:user_project_test)
    Network.where(parent_network_id: networks(:netone).id).inactive.update_all(deployment_id: other.id)

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { flunk "must not provision" }) do
      assert_equal false, @service.perform
    end

    assert @event.event_details.where(event_code: "84a4f325917d03ee").exists?
    assert_nil Network.find_by(deployment_id: @project.id)
  end

  class FailingProvisioner
    def perform
      false
    end
  end

  class PassingProvisioner
    def perform
      true
    end
  end
end
