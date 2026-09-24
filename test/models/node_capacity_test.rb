require "test_helper"

##
# Node capacity: the persisted cpu_cores / memory_mb columns, the nil-means-unknown
# contract of #total_cpu_cores / #total_memory_mb, and what #can_accept_package? does
# with an unknown answer.
#
# The whole point of this file is the FAIL-OPEN behaviour. Both live readers answer
# zero when the metrics server is unreachable, and BillingPackage validates cpu > 0 /
# memory >= 256, so a zero used to reject every candidate node in the fleet -- an
# unreachable Prometheus failed customer orders everywhere.
#
# NOTE, and it is the reason every test below stubs: Nodes::NodeMetrics short-circuits
# metric_cpu_cores / metric_memory to a fixed 2 cores / 2048 MB under Rails.env.test?.
# No test can produce an unknown capacity without replacing those readers.
class NodeCapacityTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    assert_nil @node.cpu_cores, "fixture must start with no persisted capacity"
    assert_nil @node.memory_mb
  end

  # --- the readers ------------------------------------------------------------------

  test "total_cpu_cores prefers the persisted column over the live read" do
    @node.update_columns(cpu_cores: 64)
    assert_equal 64, @node.total_cpu_cores
  end

  test "total_memory_mb prefers the persisted column over the live read" do
    @node.update_columns(memory_mb: 262_144)
    assert_equal 262_144, @node.total_memory_mb
  end

  test "falls back to the live read when the columns are NULL" do
    # The test-env short-circuit IS the live read here: 2 cores / 2048 MB.
    assert_equal 2, @node.total_cpu_cores
    assert_equal 2048, @node.total_memory_mb
  end

  test "a zero live read is unknown, not zero" do
    with_dead_metrics do
      node = Node.find(@node.id)
      assert_nil node.total_cpu_cores
      assert_nil node.total_memory_mb
    end
  end

  test "a zero persisted column falls through to the live read rather than reporting zero" do
    # Nothing should ever write a zero, but a hand-edited row must not be able to make
    # a node look like it has no CPUs.
    @node.update_columns(cpu_cores: 0, memory_mb: 0)
    assert_equal 2, @node.total_cpu_cores
    assert_equal 2048, @node.total_memory_mb
  end

  # --- can_accept_package? ----------------------------------------------------------

  test "rejects a node that is genuinely too small" do
    @node.update_columns(cpu_cores: 1, memory_mb: 1024)
    refute @node.can_accept_package?(BillingPackage.new(cpu: 4, memory: 512))
    assert_equal 4.0, @node.context.dig(:node_system_cpu_cores, :requested_cpu)
  end

  test "rejects a node with too little memory" do
    @node.update_columns(cpu_cores: 16, memory_mb: 1024)
    refute @node.can_accept_package?(BillingPackage.new(cpu: 1, memory: 4096))
    assert_equal 4096, @node.context.dig(:node_system_memory, :requested_memory)
  end

  test "accepts a node that is large enough" do
    @node.update_columns(cpu_cores: 16, memory_mb: 32_768)
    assert @node.can_accept_package?(BillingPackage.new(cpu: 1, memory: 512))
  end

  ##
  # THE test. An implementation that rejects on unknown capacity fails here, and that
  # implementation is what took orders down fleet-wide whenever Prometheus was
  # unreachable. Unknown must ABSTAIN.
  test "accepts when capacity is unknown" do
    with_dead_metrics do
      node = Node.find(@node.id)
      assert_nil node.total_cpu_cores, "precondition: capacity must be unknown"
      assert_nil node.total_memory_mb
      assert node.can_accept_package?(BillingPackage.new(cpu: 4, memory: 8192)),
        "unknown capacity must fail OPEN -- a node we cannot measure is not a node we reject"
    end
  end

  test "the overcommit gates also abstain when capacity is unknown" do
    # Both flags off, so the second pair of checks -- total minus allocated -- runs too.
    locations(:testlocation).update!(overcommit_cpu: false, overcommit_memory: false)
    with_dead_metrics do
      node = Node.find(@node.id)
      assert node.can_accept_package?(BillingPackage.new(cpu: 1, memory: 512))
    end
  end

  test "the overcommit gates still reject a committed node whose capacity IS known" do
    locations(:testlocation).update!(overcommit_cpu: false)
    @node.update_columns(cpu_cores: 2, memory_mb: 32_768)
    fill_node(@node, cpu: 2, memory: 128)

    refute @node.can_accept_package?(BillingPackage.new(cpu: 1, memory: 512))
    assert @node.context.key?(:no_overcommit_cpu)
  end

  # --- Item B: memoisation ----------------------------------------------------------

  test "the live cpu reader is called once per instance" do
    node = Node.find(@node.id)
    calls = count_live_reads(node)
    3.times { node.metric_cpu_cores }
    assert_equal 1, calls.count { |m| m == :cpu }
  end

  test "the live memory reader is memoised per unit, not across units" do
    node = Node.find(@node.id)
    calls = count_live_reads(node)
    2.times { node.metric_memory(:MB) }
    2.times { node.metric_memory(:GB) }
    # One read per unit -- :GB and :MB are different numbers from the same query, so a
    # single memo slot would hand one caller the other caller's units.
    assert_equal 2, calls.count { |m| m == :memory }
  end

  test "memoisation does not leak between instances" do
    a = Node.find(@node.id)
    b = Node.find(@node.id)
    a.metric_cpu_cores
    calls = count_live_reads(b)
    b.metric_cpu_cores
    assert_equal 1, calls.count { |m| m == :cpu }
  end

  private

  # Replace the LIVE readers -- not total_*, which is what is under test -- with the
  # zeroes an unreachable Prometheus produces. Defined on Node so it wins over
  # Nodes::NodeMetrics, and removed afterwards so the concern's versions show through
  # again. (There is no mocha in this project and minitest's #stub only covers a single
  # object; find_node loads its own Node instances.)
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

  # Record every call that reaches the un-memoised reader on ONE instance.
  def count_live_reads(node)
    seen = []
    node.define_singleton_method(:read_metric_cpu_cores) do
      seen << :cpu
      {time: Time.now, cpu: 2}
    end
    node.define_singleton_method(:read_metric_memory) do |unit = :GB|
      seen << :memory
      {time: Time.now, memory: (unit == :GB) ? 2 : 2048}
    end
    seen
  end

  def fill_node(node, cpu:, memory:)
    project = Deployment.create!(user: users(:admin), name: "cap_#{SecureRandom.hex(4)}")
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
