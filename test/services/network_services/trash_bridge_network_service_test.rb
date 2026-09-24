require "test_helper"
require "minitest/mock"

##
# The rule under test: `active: false` is the release. Once it is cleared the row can be
# reallocated and RENAMED, and the name is the only handle anything has on the docker
# network -- so a copy still on a node at that moment is lost for good, and it holds the
# subnet. Docker then refuses the next create on that row with 403 Forbidden.
#
# So the release must happen only when every online node was positively confirmed clean.
class NetworkServices::TrashBridgeNetworkServiceTest < ActiveSupport::TestCase
  setup do
    @network = networks(:net_gen_1)
    @network.update! active: true, deployment: nil
    @service = NetworkServices::TrashBridgeNetworkService.new(@network)
  end

  # A network object that records whether remove was called, and can be told to refuse.
  class FakeNetwork
    attr_reader :removals

    def initialize(error: nil)
      @error = error
      @removals = 0
    end

    def remove
      @removals += 1
      raise @error if @error
      nil
    end
  end

  test "a network that is already off every node releases the row" do
    Docker::Network.stub(:get, ->(*) { raise Docker::Error::NotFoundError }) do
      assert_equal true, @service.perform
    end

    assert_equal false, @network.reload.active
  end

  test "removing the network from the node releases the row" do
    fake = FakeNetwork.new

    Docker::Network.stub(:get, ->(*) { fake }) do
      assert_equal true, @service.perform
    end

    assert_equal 1, fake.removals
    assert_equal false, @network.reload.active
  end

  # The regression. A transient error looking the network up used to `next` and then fall
  # through to make_ready! anyway, which is how a live docker network ended up holding the
  # subnet of a row that had been handed to someone else.
  test "a node that cannot be reached does NOT release the row" do
    Docker::Network.stub(:get, ->(*) { raise "connection refused" }) do
      assert_equal false, @service.perform
    end

    assert_equal true, @network.reload.active, "the row must stay out of the allocation pool"
  end

  # Docker refuses to remove a network that still has endpoints attached. That is a real
  # "still on the node" answer, not a transient one, and it must block the release too.
  test "a removal docker refuses does NOT release the row" do
    fake = FakeNetwork.new(error: Docker::Error::ConflictError.new("has active endpoints"))

    Docker::Network.stub(:get, ->(*) { fake }) do
      assert_equal false, @service.perform
    end

    assert_equal 1, fake.removals
    assert_equal true, @network.reload.active
  end

  # PrivateNetCleanupWorker is retry: false and loops over every network in the region. A
  # raise out of here used to kill the rest of that sweep silently.
  test "a removal failure is contained rather than raised at the caller" do
    fake = FakeNetwork.new(error: Docker::Error::ConflictError.new("has active endpoints"))

    Docker::Network.stub(:get, ->(*) { fake }) do
      assert_nothing_raised { @service.perform }
    end
  end

  test "a row that still has a project is never touched" do
    @network.update! deployment: deployments(:project_test)

    assert_equal false, @service.perform
    assert_equal true, @network.reload.active
  end

  test "an offline node in the region defers the release" do
    nodes(:testone).update! disconnected: true

    assert_equal false, @service.perform
    assert_equal true, @network.reload.active
  end

  # Without this guard the each-loop is vacuously satisfied and the row is released with no
  # node ever consulted.
  test "a region with no nodes defers the release rather than releasing unchecked" do
    @network.region.stub(:nodes, Node.none) do
      assert_equal false, @service.perform
    end

    assert_equal true, @network.reload.active
  end
end
