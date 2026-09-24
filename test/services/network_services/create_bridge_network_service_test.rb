require "test_helper"
require "minitest/mock"

class NetworkServices::CreateBridgeNetworkServiceTest < ActiveSupport::TestCase
  setup do
    @region = regions(:regionone)
    @node = nodes(:testone)
    @network = networks(:test_project_net)
    @network.deployment = deployments(:project_test)
    # A network about to be created is not on a node yet. Saving here also normalises the
    # fixture's name through Network#format_network_name, so tests compare like with like.
    @network.update! active: false
    @service = NetworkServices::CreateBridgeNetworkService.new(@network, nil)
  end

  # The v4 payload as it exists today, on docker 28+.
  def expected_v4_params
    {
      "IPAM" => {
        "Config" => [{"Subnet" => @network.to_net}]
      },
      "Labels" => {
        "com.computestacks.deployment_id" => deployments(:project_test).id.to_s,
        "com.computestacks.network_id" => @network.id.to_s
      },
      "Options" => {
        "com.docker.network.bridge.gateway_mode_ipv4" => "nat-unprotected"
      }
    }
  end

  def params_for(docker_major_version)
    @service.network_params_for(docker_major_version)
  end

  test "EnableIPv6 is absent when the region flag is off" do
    assert_equal false, @region.ipv6_egress?

    params = params_for(29)

    assert_not params.key?("EnableIPv6")
    assert_equal expected_v4_params, params
  end

  test "EnableIPv6 is present when the region flag is on" do
    @region.update! ipv6_egress: true
    @network.reload
    @network.deployment = deployments(:project_test)

    params = params_for(29)

    assert_equal true, params["EnableIPv6"]
    # ... and nothing about the v4 payload changed.
    assert_equal expected_v4_params, params.except("EnableIPv6")
  end

  test "EnableIPv6 is a top level key, not part of IPAM" do
    @region.update! ipv6_egress: true
    @network.reload
    @network.deployment = deployments(:project_test)

    params = params_for(29)

    assert_equal [{"Subnet" => @network.to_net}], params["IPAM"]["Config"]
    assert_not params["IPAM"].key?("EnableIPv6")
  end

  test "EnableIPv6 is absent on docker older than 28 even when the flag is on" do
    @region.update! ipv6_egress: true
    @network.reload
    @network.deployment = deployments(:project_test)

    params = params_for(27)

    assert_not params.key?("EnableIPv6")
    # Pre-28 nodes also get no Options -- unchanged from today.
    assert_equal expected_v4_params.except("Options"), params
  end

  # An unknown docker version must never reach the payload builder: silently omitting
  # `gateway_mode_ipv4` would create a network on docker 28+ whose published ports are all
  # dropped, and mark it active. The caller gates on nil; this pins that contract so nobody
  # reintroduces tolerance here.
  test "an unknown docker version is never tolerated by the payload builder" do
    assert_raises(NoMethodError) { params_for(nil) }
  end

  # The loop `next`s any node whose docker version is unknown, so a run where no node
  # produced a network must not mark the network active -- and must say so somewhere an
  # admin will look. Before this, that path returned false in silence and its caller
  # discarded the value, so the order still reported success.
  test "creating on no node writes an event detail instead of failing silently" do
    event = EventLog.create!(
      locale: "network.create",
      locale_keys: {"network" => @network.name},
      event_code: "29c824a801b8866d",
      status: "pending"
    )
    service = NetworkServices::CreateBridgeNetworkService.new(@network, event)

    @network.region.stub(:nodes, Node.none) do
      assert_equal false, service.perform
    end

    detail = event.event_details.reload.last
    assert_not_nil detail, "the empty-results path must record why nothing was created"
    assert_match "No online node accepted it", detail.data
    assert_match @network.name, detail.data
  end

  test "a failed create writes an event detail naming the network and the ipv6 request" do
    @region.update! ipv6_egress: true
    @network.reload
    event = EventLog.create!(
      locale: "network.create",
      locale_keys: {"network" => @network.name},
      event_code: "29c824a801b8866d",
      status: "pending"
    )
    service = NetworkServices::CreateBridgeNetworkService.new(@network, event)

    # Force the rescue path.
    @network.region.stub(:nodes, -> { raise "boom" }) do
      assert_equal false, service.perform
    end

    detail = event.event_details.reload.last
    assert_not_nil detail
    assert_equal "29c824a801b8866d", detail.event_code
    assert_match @network.name, detail.data
    assert_match "Failed to provision network", detail.data
    assert_match "IPv6 egress requested: true", detail.data
    assert_match "boom", detail.data
  end

  test "a failed create records the flag as off when the region does not have it set" do
    event = EventLog.create!(
      locale: "network.create",
      locale_keys: {"network" => @network.name},
      event_code: "29c824a801b8866d",
      status: "pending"
    )
    service = NetworkServices::CreateBridgeNetworkService.new(@network, event)

    @network.region.stub(:nodes, -> { raise "boom" }) do
      assert_equal false, service.perform
    end

    assert_match "IPv6 egress requested: false", event.event_details.reload.last.data
  end
  # --- reclaiming a renamed copy ------------------------------------------------------
  #
  # Allocation renames the row (GenerateProjectNetworkService), so a docker network left on
  # a node at release time keeps the OLD name while the row moves on. Checking by name alone
  # cannot see it, and it still holds the row's subnet -- docker answers the create with 403
  # Forbidden ("Pool overlaps with other one on this address space"). The id label is the only
  # thing that still ties the two together.

  class FakeDockerNetwork
    attr_reader :info, :removals

    def initialize(info)
      @info = info
      @removals = 0
    end

    def remove
      @removals += 1
      nil
    end
  end

  # A stand-in for `region.nodes` that answers `online`. The real relation would need a
  # database round trip to filter, and the node needs singleton stubs anyway.
  class FakeNodes
    def initialize(list)
      @list = list
    end

    def online
      @list
    end
  end

  def prepared_node
    node = nodes(:testone)
    # A live probe against a fixture node's address would fail and make the loop `next`.
    def node.docker_major_version
      29
    end
    node
  end

  # The shape Docker::Container.all({all: true}) yields.
  class FakeContainer
    attr_reader :info

    def initialize(name, networks = [])
      @info = {
        "Names" => ["/#{name}"],
        "NetworkSettings" => {"Networks" => networks.to_h { |n| [n, {}] }}
      }
    end
  end

  ##
  # @param present [Hash] docker network name => object, for Docker::Network.get
  # @param listed [Array] what Docker::Network.all answers
  # @param containers [Array, Proc] what Docker::Container.all answers; a Proc is called, so
  #   a test can make the listing raise
  def with_docker(present:, listed:, containers: [])
    getter = lambda do |name, *_args|
      raise Docker::Error::NotFoundError unless present.key?(name)
      present[name]
    end
    container_all = containers.is_a?(Proc) ? containers : ->(*) { containers }
    Docker::Network.stub(:get, getter) do
      Docker::Network.stub(:all, ->(*) { listed }) do
        Docker::Container.stub(:all, container_all) do
          yield
        end
      end
    end
  end

  def orphan_for(network, name:, containers: {})
    FakeDockerNetwork.new(
      "Name" => name,
      "Labels" => {"com.computestacks.network_id" => network.id.to_s},
      "Containers" => containers
    )
  end

  test "a copy left under an older name is removed before the network is created" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject")
    created = []

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {"netoldproject" => orphan}, listed: [orphan]) do
        Docker::Network.stub(:create, ->(name, *_args) {
          created << name
          Docker::Network.new(node.client(5), {"Id" => "abc123"})
        }) do
          assert_equal true, @service.perform
        end
      end
    end

    assert_equal 1, orphan.removals, "the stale copy holding our subnet must be removed"
    assert_equal [@network.name], created
    assert_equal true, @network.reload.active
  end

  test "reclaiming a copy records it for the operator" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject")

    assert_difference "SystemEvent.count", 1 do
      @network.region.stub(:nodes, FakeNodes.new([node])) do
        with_docker(present: {"netoldproject" => orphan}, listed: [orphan]) do
          Docker::Network.stub(:create, ->(*) { Docker::Network.new(node.client(5), {"Id" => "abc123"}) }) do
            @service.perform
          end
        end
      end
    end

    system_event = SystemEvent.sorted.first
    assert_equal NetworkServices::CreateBridgeNetworkService::RECLAIMED_EVENT_CODE, system_event.event_code
    assert_equal "netoldproject", system_event.data[:removed]
  end

  # A network with endpoints on it is live, whatever the database thinks. Removing it would
  # cut those containers off the network, so the create is abandoned instead.
  test "a copy with containers attached is left alone and the create does not proceed" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject",
      containers: {"deadbeef" => {"Name" => "someones-running-container"}})
    event = EventLog.create!(
      locale: "network.create",
      locale_keys: {"network" => @network.name},
      event_code: "29c824a801b8866d",
      status: "pending"
    )
    service = NetworkServices::CreateBridgeNetworkService.new(@network, event)
    created = []

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {"netoldproject" => orphan}, listed: [orphan]) do
        Docker::Network.stub(:create, ->(name, *_args) { created << name }) do
          assert_equal false, service.perform
        end
      end
    end

    assert_equal 0, orphan.removals, "a network with live endpoints must never be removed"
    assert_empty created, "creating over a held subnet would just fail with 403"
    assert_equal false, @network.reload.active
  end

  test "a blocked reclaim tells the operator what is holding the subnet, and the customer only the zone" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject",
      containers: {"deadbeef" => {"Name" => "someones-running-container"}})
    event = EventLog.create!(
      locale: "network.create",
      locale_keys: {"network" => @network.name},
      event_code: "29c824a801b8866d",
      status: "pending"
    )
    service = NetworkServices::CreateBridgeNetworkService.new(@network, event)

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {"netoldproject" => orphan}, listed: [orphan]) do
        Docker::Network.stub(:create, ->(*) { nil }) do
          service.perform
        end
      end
    end

    system_event = SystemEvent.sorted.first
    assert_equal NetworkServices::CreateBridgeNetworkService::RECLAIM_BLOCKED_EVENT_CODE, system_event.event_code
    assert_equal "netoldproject", system_event.data[:blocked_by]
    assert_equal ["deadbeef"], system_event.data[:attached_containers]

    detail = event.event_details.reload.detect { |d| d.data.include?("address range") }
    assert_not_nil detail, "the customer must be told the order failed"
    assert_no_match "netoldproject", detail.data
    assert_no_match "deadbeef", detail.data
  end

  # Only THIS row's label counts. Another project's network on the same node is none of our
  # business, and removing it would take that project offline.
  test "a network belonging to a different row is not touched" do
    node = prepared_node
    other = networks(:net_gen_2)
    stranger = FakeDockerNetwork.new(
      "Name" => other.name,
      "Labels" => {"com.computestacks.network_id" => other.id.to_s},
      "Containers" => {}
    )

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {other.name => stranger}, listed: [stranger]) do
        Docker::Network.stub(:create, ->(*) { Docker::Network.new(node.client(5), {"Id" => "abc123"}) }) do
          assert_equal true, @service.perform
        end
      end
    end

    assert_equal 0, stranger.removals
  end

  # The name matching is what tells "our copy, stale" from "our copy, current".
  test "a copy already under the current name is not removed" do
    node = prepared_node
    current = orphan_for(@network, name: @network.name)

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {@network.name => current}, listed: [current]) do
        # Step 1 sees a non-empty info for our own name and skips the node entirely.
        assert_equal false, @service.perform
      end
    end

    assert_equal 0, current.removals
  end

  # A stopped container holds no endpoint, so `Containers` is empty and docker removes the
  # network without complaint -- and that container can then never start again. The container
  # list is the only signal that sees it.
  test "a copy a stopped container still uses is not reclaimed" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject")
    stopped = FakeContainer.new("someones-stopped-container", ["netoldproject"])
    created = []

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {"netoldproject" => orphan}, listed: [orphan], containers: [stopped]) do
        Docker::Network.stub(:create, ->(name, *_args) { created << name }) do
          assert_equal false, @service.perform
        end
      end
    end

    assert_equal 0, orphan.removals
    assert_empty created
    assert_match "including stopped ones", SystemEvent.sorted.first.data[:reason]
  end

  test "a container list that cannot be read blocks the reclaim rather than assuming nothing uses it" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject")

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {"netoldproject" => orphan}, listed: [orphan],
        containers: ->(*) { raise "connection refused" }) do
        Docker::Network.stub(:create, ->(*) { nil }) do
          assert_equal false, @service.perform
        end
      end
    end

    assert_equal 0, orphan.removals
    assert_match "could not be read", SystemEvent.sorted.first.data[:reason]
  end

  # A container attaching between the checks and the remove. Letting it unwind would abandon
  # every remaining node in the region and put docker's raw message on a customer event.
  test "a removal docker refuses is contained rather than aborting the whole region" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject")
    def orphan.remove
      @removals = (@removals || 0) + 1
      raise Docker::Error::ConflictError, "has active endpoints"
    end
    event = EventLog.create!(
      locale: "network.create", locale_keys: {"network" => @network.name},
      event_code: "29c824a801b8866d", status: "pending"
    )
    service = NetworkServices::CreateBridgeNetworkService.new(@network, event)

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {"netoldproject" => orphan}, listed: [orphan]) do
        Docker::Network.stub(:create, ->(*) { nil }) do
          assert_equal false, service.perform
        end
      end
    end

    assert_no_match "active endpoints", event.event_details.reload.map(&:data).join("\n")
  end

  # The node answered perfectly well. Telling the customer it "may be offline or its docker
  # daemon unreachable" on top of the real reason sends support down the wrong path.
  test "a blocked reclaim does not also claim the node was unreachable" do
    node = prepared_node
    orphan = orphan_for(@network, name: "netoldproject",
      containers: {"deadbeef" => {"Name" => "someones-running-container"}})
    event = EventLog.create!(
      locale: "network.create", locale_keys: {"network" => @network.name},
      event_code: "29c824a801b8866d", status: "pending"
    )
    service = NetworkServices::CreateBridgeNetworkService.new(@network, event)

    @network.region.stub(:nodes, FakeNodes.new([node])) do
      with_docker(present: {"netoldproject" => orphan}, listed: [orphan]) do
        Docker::Network.stub(:create, ->(*) { nil }) do
          service.perform
        end
      end
    end

    details = event.event_details.reload.map(&:data).join("\n")
    assert_match "address range", details
    assert_no_match "may be offline", details
  end
end
