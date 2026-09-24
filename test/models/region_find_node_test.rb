require "test_helper"

##
# Region#find_node and Region#current_allocated_usage under an unreachable metrics
# server, plus the order the placement gates run in.
#
# The end-to-end nil tests here are the important ones. Before capacity was persisted,
# every node's cpu/memory came from Prometheus on every order; the readers rescued to
# zero, so a metrics outage rejected the entire fleet. Now the readers answer nil for
# unknown, and nil reaches arithmetic in two places -- find_node's ranking and the
# zone's capacity sum. Neither may raise, and find_node must still place the node.
class RegionFindNodeTest < ActiveSupport::TestCase
  setup do
    @region = regions(:regionone)
    @node = nodes(:testone)
    @package = BillingPackage.new(cpu: 1, memory: 512)
    assert_nil @node.cpu_cores, "fixture must start with no persisted capacity"
  end

  # --- unknown capacity end to end --------------------------------------------------

  test "find_node still places a node when the columns are NULL and the metrics server is down" do
    with_dead_metrics do
      selected = @region.find_node(@package)
      assert_equal @node, selected,
        "an unreadable capacity must not disqualify the only node in the zone"
    end
  end

  test "find_node ranks an unmeasurable node rather than raising on nil arithmetic" do
    # fill_by_qty off forces the resource ranking, which is where total_* meets
    # subtraction. With one candidate it must still come back with that candidate.
    locations(:testlocation).update!(fill_by_qty: false)
    with_dead_metrics do
      assert_equal @node, @region.reload.find_node(@package)
    end
  end

  test "find_node ranks a measurable node above one whose capacity cannot be read" do
    locations(:testlocation).update!(fill_by_qty: false)
    known = @region.nodes.create!(label: "known", hostname: "known", active: true,
      primary_ip: "127.0.0.50", public_ip: "127.0.0.50")
    known.update_columns(cpu_cores: 64, memory_mb: 262_144)

    with_dead_metrics do
      # The unmeasurable node is not rejected -- it is simply ranked worst, which is
      # exactly where a failed Prometheus read used to put it.
      assert_equal known, @region.reload.find_node(@package)
    end
  end

  test "current_allocated_usage returns a figure rather than raising on a nil member" do
    # Enumerable#sum starts at the integer 0, and 0 + nil is a TypeError. One node with
    # a NULL column and a dead metrics server would otherwise take the zone figure down.
    with_dead_metrics do
      usage = nil
      assert_nothing_raised { usage = Region.find(@region.id).current_allocated_usage }
      assert_equal 0, usage[:cpu][:available]
      assert_equal 0, usage[:memory][:available]
      assert_equal 100, usage[:cpu][:usage]
      assert_equal 100, usage[:memory][:usage]
    end
  end

  test "current_allocated_usage sums the persisted columns" do
    @node.update_columns(cpu_cores: 8, memory_mb: 16_384)
    second = @region.nodes.create!(label: "second", hostname: "second", active: true,
      primary_ip: "127.0.0.51", public_ip: "127.0.0.51")
    second.update_columns(cpu_cores: 4, memory_mb: 8192)

    usage = Region.find(@region.id).current_allocated_usage
    assert_equal 12, usage[:cpu][:available]
    assert_equal 24_576, usage[:memory][:available]
  end

  # --- Item B2: the cheap gates run before the expensive one -------------------------

  test "an evacuating node is skipped without asking about its capacity" do
    evacuating = @region.nodes.create!(label: "evac", hostname: "evac", active: true,
      primary_ip: "127.0.0.52", public_ip: "127.0.0.52")
    evacuating.update!(job_status: "evacuating", job_performed: Time.now)

    asked = nil
    selected = record_capacity_gate { |seen| asked = seen; @region.reload.find_node(@package) }

    assert_equal @node, selected
    refute_includes asked, "evac",
      "nodes.available does not exclude evacuating nodes, and an evacuating node never " \
      "heartbeats -- asking it about capacity means a Prometheus fallback on every order"
    assert_includes asked, @node.label
  end

  test "a filled node is skipped without asking about its capacity" do
    # fill_to 1, and the fixture node already carries containers -- exclude it so the
    # only two candidates are one node at its fill limit and one empty node.
    @region.update!(fill_to: 1)
    filled = @region.nodes.create!(label: "filled", hostname: "filled", active: true,
      primary_ip: "127.0.0.53", public_ip: "127.0.0.53")
    fill_node(filled, cpu: 0.1, memory: 128)
    spare = @region.nodes.create!(label: "spare", hostname: "spare", active: true,
      primary_ip: "127.0.0.58", public_ip: "127.0.0.58")

    asked = nil
    selected = record_capacity_gate { |seen|
      asked = seen
      Region.find(@region.id).find_node(@package, [@node.id])
    }

    assert_equal spare, selected
    refute_includes asked, "filled"
    assert_includes asked, "spare"
  end

  ##
  # The reorder's whole claim: all three are `next`-style filters, so the surviving
  # candidate SET -- and therefore the selection -- cannot move. Exercise a candidate
  # list that trips every one of the three and check who comes out.
  test "selection is unchanged for a candidate set exercising evacuation, fill_to and capacity" do
    # fill_to 1 also disqualifies the fixture node, which already carries containers.
    @region.update!(fill_to: 1)

    evacuating = @region.nodes.create!(label: "a-evac", hostname: "a-evac", active: true,
      primary_ip: "127.0.0.54", public_ip: "127.0.0.54")
    evacuating.update_columns(cpu_cores: 64, memory_mb: 262_144)
    evacuating.update!(job_status: "evacuating", job_performed: Time.now)

    filled = @region.nodes.create!(label: "b-filled", hostname: "b-filled", active: true,
      primary_ip: "127.0.0.55", public_ip: "127.0.0.55")
    filled.update_columns(cpu_cores: 64, memory_mb: 262_144)
    fill_node(filled, cpu: 0.1, memory: 128)

    undersized = @region.nodes.create!(label: "c-small", hostname: "c-small", active: true,
      primary_ip: "127.0.0.56", public_ip: "127.0.0.56")
    undersized.update_columns(cpu_cores: 1, memory_mb: 256)

    survivor = @region.nodes.create!(label: "d-ok", hostname: "d-ok", active: true,
      primary_ip: "127.0.0.57", public_ip: "127.0.0.57")
    survivor.update_columns(cpu_cores: 32, memory_mb: 131_072)

    region = Region.find(@region.id)
    assert_equal survivor, region.find_node(BillingPackage.new(cpu: 2, memory: 2048))

    # Each of the three gates still fires, and still attributes its own rejection --
    # only the order they run in changed.
    assert region.context.dig(:"a-evac", :evacuation)
    assert region.context.dig(:"b-filled", :filled)
    assert region.context.dig(:"c-small", :package_unable)
    refute region.context.key?(:"d-ok")
  end

  private

  # See NodeCapacityTest#with_dead_metrics. Defined on Node rather than on an instance
  # because find_node loads its own Node objects out of the association.
  def with_dead_metrics
    Node.class_eval do
      def metric_cpu_cores
        {time: Time.now, cpu: 0}
      end

      def metric_memory(unit = :GB)
        {time: Time.now, memory: 0}
      end
    end
    yield
  ensure
    Node.send(:remove_method, :metric_cpu_cores)
    Node.send(:remove_method, :metric_memory)
  end

  # Yields the array that collects the label of every node can_accept_package? is
  # asked about, then returns the block's value.
  def record_capacity_gate
    seen = []
    Node.class_eval do
      alias_method :orig_can_accept_package?, :can_accept_package?
      define_method(:can_accept_package?) do |package|
        seen << label
        orig_can_accept_package?(package)
      end
    end
    yield seen
  ensure
    Node.send(:remove_method, :can_accept_package?)
    Node.send(:remove_method, :orig_can_accept_package?)
  end

  def fill_node(node, cpu:, memory:)
    project = Deployment.create!(user: users(:admin), name: "fn_#{SecureRandom.hex(4)}")
    service = project.services.create!(
      name: "svc#{SecureRandom.hex(3)}",
      container_image: ContainerImage.first,
      region: node.region
    )
    service.containers.create!(
      name: "c#{SecureRandom.hex(3)}",
      node: node,
      cpu: cpu,
      memory: memory
    )
  end
end
