require "test_helper"
require "minitest/mock"

##
# `finalize!` runs AFTER every container, subscription and volume in the order is already
# built — so anything it records in `errors` fails an order whose resources exist, and
# fail_process! then releases the project's private network. Only genuinely unrecoverable
# work belongs in `errors` here; self-healing conditions belong on the event.
class ProcessOrderServiceTest < ActiveSupport::TestCase
  # Stand-in for the provisioners finalize! calls. Reports success and no errors, so the
  # only thing under test is the agent-tenant branch.
  class FakeProvisioner
    attr_accessor :volume_clones

    def perform = true

    def errors = []
  end

  setup do
    @project = deployments(:project_test)
    @event = EventLog.create!(
      locale: "order.provision",
      event_code: "0a3af01a3384fa10",
      audit: Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "created"),
      status: "pending"
    )
    @service = ProcessOrderService.new(Order.new)
    @service.project = @project
    @service.region = regions(:regionone)
    @service.event = @event
  end

  # Replace the downstream provisioners with successful fakes so the assertion is about
  # the agent-tenant branch alone, then run the real finalize!.
  def finalize_with_agent(agent_new)
    fake = FakeProvisioner.new
    Agent::Client.stub(:new, agent_new) do
      ProvisionServices::SftpProvisioner.stub(:new, ->(*) { fake }) do
        ProjectServices::MetadataSshKeys.stub(:new, ->(*) { fake }) do
          DeployServices::DeployProjectService.stub(:new, ->(*) { fake }) do
            @service.send(:finalize!)
          end
        end
      end
    end
  end

  test "an agent that is not ready does not fail an order whose resources are already built" do
    not_ready = ->(*, **) { raise Agent::Client::NotReady, "node 1 has no agent_token" }

    assert finalize_with_agent(not_ready), "finalize! must not fail on a NotReady agent"
    assert_empty @service.errors

    detail = @event.event_details.find_by(event_code: "7239068cdeb3b779")
    refute_nil detail, "the skipped tenant provisioning must be recorded on the event"
    assert_match "node 1 has no agent_token", detail.data
  end

  test "the tenant is provisioned with the project's metadata bearer" do
    provisioned = []
    client = Object.new
    client.define_singleton_method(:provision_tenant!) { provisioned << true }

    assert finalize_with_agent(->(*, **) { client })
    assert_equal [true], provisioned
    assert @project.reload.consul_auth_key.present?, "expected the metadata bearer to be minted"
  end

  # --- releasing the project's private network on failure -------------------------------
  #
  # Detaching the row is not a release. The row stays `active`, and `active` is the only
  # thing keeping it out of GenerateProjectNetworkService's allocation pool -- so a row
  # detached but left active is correctly parked, and one whose docker network is gone must
  # be handed back. TrashBridgeNetworkService is what draws that line; fail_process! must
  # actually call it, and must never raise while doing so.

  test "releasing the network detaches the row and trashes it on the node" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project

    Docker::Network.stub(:get, ->(*) { raise Docker::Error::NotFoundError }) do
      @service.send(:release_network!)
    end

    network.reload
    assert_nil network.deployment_id
    assert_equal false, network.active, "a network confirmed off the node returns to the pool"
  end

  # The other half: a node that cannot confirm the removal leaves the row active, so it is
  # not handed to the next project while a copy still holds its subnet.
  test "releasing the network leaves the row parked when the node cannot confirm" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project

    Docker::Network.stub(:get, ->(*) { raise "connection refused" }) do
      @service.send(:release_network!)
    end

    network.reload
    assert_nil network.deployment_id
    assert_equal true, network.active
  end

  # fail_process! runs on the failure path, including from perform's ensure. A raise here
  # would replace the real failure with this one.
  test "releasing the network never raises" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project

    NetworkServices::TrashBridgeNetworkService.stub(:new, ->(*) { raise "boom" }) do
      assert_nothing_raised { @service.send(:release_network!) }
    end

    assert_nil network.reload.deployment_id
  end

  test "releasing the network is a no-op when the project has none" do
    Network.where(deployment_id: @project.id).update_all(deployment_id: nil)
    @project.reload

    assert_nothing_raised { @service.send(:release_network!) }
  end

  # Order stand-in: ProcessOrderService#initialize reads these three, and fail_process! calls
  # fail!. An unsaved Order can't do the last one.
  class FakeOrder
    attr_reader :failed

    def current_event = nil

    def deployment = nil

    def data = {}

    def fail!
      @failed = true
    end
  end

  # Records the row's state at the moment TrashBridgeNetworkService is handed it.
  class RecordingTrasher
    class << self
      attr_accessor :seen, :calls
    end

    def initialize(network)
      self.class.calls = self.class.calls.to_i + 1
      self.class.seen = [network.active, network.deployment_id]
    end

    def perform
      false
    end
  end

  # The wiring, not just the method: deleting the call from fail_process! must fail something.
  test "failing an order releases its private network" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project
    service = ProcessOrderService.new(FakeOrder.new)
    service.project = @project
    service.event = @event
    service.errors = []

    Docker::Network.stub(:get, ->(*) { raise Docker::Error::NotFoundError }) do
      service.send(:fail_process!, "boom")
    end

    network.reload
    assert_nil network.deployment_id
    assert_equal false, network.active
  end

  # The allocation pool is "inactive AND no project". A network whose create failed is already
  # inactive, so detaching it first would put it in the pool before anything had established
  # that it is off the node -- the same ordering inversion this whole change exists to fix.
  test "an unconfirmed network is marked active before it is detached" do
    network = networks(:net_gen_1)
    network.update! active: false, deployment: @project
    RecordingTrasher.seen = nil
    RecordingTrasher.calls = 0

    NetworkServices::TrashBridgeNetworkService.stub(:new, ->(net) { RecordingTrasher.new(net) }) do
      @service.send(:release_network!)
    end

    assert_equal 1, RecordingTrasher.calls
    assert_equal [true, nil], RecordingTrasher.seen,
      "the row must be parked, not pooled, until the node confirms the network is gone"
    assert_equal true, network.reload.active
  end
end
