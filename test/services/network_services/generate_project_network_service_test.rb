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
