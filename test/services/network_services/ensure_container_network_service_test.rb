require "test_helper"
require "minitest/mock"

class NetworkServices::EnsureContainerNetworkServiceTest < ActiveSupport::TestCase
  setup do
    @project = deployments(:project_test)
    @container = deployment_containers(:wordpress_1)
    # Start from a project with no network of its own; each test sets up what it needs.
    Network.where(deployment_id: @project.id).update_all(deployment_id: nil)
    @network = networks(:net_gen_0)
    @event = EventLog.create!(
      locale: "container.provision",
      event_code: "7a1d9e6b0c3f2a15",
      status: "running"
    )
  end

  test "ready, and a no-op, when the network and IP are already in place" do
    bind_network!(active: true)

    assert_no_difference -> { EventLogDatum.count } do
      assert_equal :ready, perform
    end
    assert_nil @service.reason
  end

  test "assigns a missing IP when the network exists" do
    bind_network!(active: true)
    @container.ip_address.destroy!

    assert_no_difference -> { EventLog.count } do
      assert_equal :ready, perform
    end

    assert_equal @network.id, @container.reload.ip_address.network_id
    assert detail?(NetworkServices::EnsureContainerNetworkService::ASSIGNED_IP_EVENT_CODE)
  end

  test "allocates a missing network, then assigns the IP" do
    @container.ip_address.destroy!

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(net, _event) { PassingProvisioner.new(net) }) do
      assert_equal :ready, perform
    end

    allocated = Network.find_by(deployment_id: @project.id)
    assert allocated.active
    assert_equal allocated.id, @container.reload.ip_address.network_id
    assert detail?(NetworkServices::EnsureContainerNetworkService::ALLOCATED_EVENT_CODE)
    assert detail?(NetworkServices::EnsureContainerNetworkService::ASSIGNED_IP_EVENT_CODE)
  end

  test "retries when no network can be allocated" do
    @container.ip_address.destroy!
    other = deployments(:user_project_test)
    Network.where(parent_network_id: networks(:netone).id).inactive.update_all(deployment_id: other.id)

    assert_equal :retry, perform
    assert_match(/allocate a private network/, @service.reason)
    assert_nil @container.reload.ip_address
  end

  test "an inactive network is re-created and becomes ready" do
    bind_network!(active: false)

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(net, _event) { PassingProvisioner.new(net) }) do
      assert_equal :ready, perform
    end

    assert @network.reload.active
    assert detail?(NetworkServices::EnsureContainerNetworkService::RECREATED_EVENT_CODE)
  end

  test "waits, without creating, for a network another worker bound moments ago" do
    @network.update!(deployment_id: @project.id, active: false)
    @container.ip_address.destroy!
    created = false

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { created = true; FailingProvisioner.new }) do
      assert_equal :retry, perform
    end

    refute created, "must not race the other worker's create"
    assert_match(/still being created/, @service.reason)
  end

  test "a clustered region builds a container that already has an IP" do
    region = @container.region
    region.stub(:has_clustered_networking?, true) do
      @container.stub(:region, region) do
        assert_equal :ready, perform
      end
    end
  end

  # CreateBridgeNetworkService skips a node that already has the network, then answers false.
  test "an inactive network whose create fails but which is on the node is marked active" do
    bind_network!(active: false)
    on_node = Docker::Network.send(:new, Docker.connection, "id" => "abc")

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { FailingProvisioner.new }) do
      Docker::Network.stub(:get, on_node) do
        assert_equal :ready, perform
      end
    end

    assert @network.reload.active
    assert detail?(NetworkServices::EnsureContainerNetworkService::MARKED_ACTIVE_EVENT_CODE)
  end

  test "retries, without alerting, while the network cannot be created" do
    bind_network!(active: false)
    @container.ip_address.destroy!
    missing = ->(*) { raise Docker::Error::NotFoundError }

    NetworkServices::CreateBridgeNetworkService.stub(:new, ->(*) { FailingProvisioner.new }) do
      Docker::Network.stub(:get, missing) do
        assert_no_difference -> { EventLog.count } do
          2.times { assert_equal :retry, perform }
        end
      end
    end

    assert_match(/could not be created on the node/, @service.reason)
    refute @network.reload.active
    assert_equal @project.id, @network.deployment_id, "the row stays bound to the project"
    assert_nil @container.reload.ip_address
  end

  test "covers SFTP containers" do
    bind_network!(active: true)
    sftp = deployment_sftp(:project_test_testone)
    sftp.ip_address.destroy!

    @service = NetworkServices::EnsureContainerNetworkService.new(sftp.reload, @event)
    assert_equal :ready, @service.perform

    assert_equal @network.id, sftp.reload.ip_address.network_id
  end

  test "fails when the container has no project" do
    @container.stub(:deployment, nil) do
      assert_equal :failed, perform
    end
    assert_match(/no project/, @service.reason)
  end

  test "never raises" do
    @container.stub(:region, ->(*) { raise "boom" }) do
      assert_equal :retry, perform
    end
    assert_match(/boom/, @service.reason)
  end

  private

  def perform
    @service = NetworkServices::EnsureContainerNetworkService.new(@container, @event)
    @service.perform
  end

  # Bound well outside IN_FLIGHT_WINDOW, so an inactive row is treated as a failed create.
  def bind_network!(active:)
    @network.update_columns(deployment_id: @project.id, active: active, updated_at: 10.minutes.ago)
  end

  def detail?(code)
    @event.event_details.where(event_code: code).exists?
  end

  class PassingProvisioner
    def initialize(net)
      @net = net
    end

    def perform
      @net.update(active: true)
      true
    end
  end

  class FailingProvisioner
    def perform
      false
    end
  end
end
