require "test_helper"
require "webmock"
require "benchmark"

# Covers Regions::RegionMetrics#resource_usage -- the four numbers on each region
# row of the admin dashboard. The behaviour under test is that the three
# Prometheus reads per node happen CONCURRENTLY (they used to be sequential,
# which cost ~4.8s for a zone a continent away from the controller) while every
# number it produces stays exactly what the sequential version produced.
class RegionResourceUsageTest < ActiveSupport::TestCase
  # Scoped to this test class -- enabling WebMock process-wide would block the
  # real HTTP other suites make.
  include WebMock::API

  MEMORY = "node_memory_MemAvailable_bytes".freeze
  CPU = "node_cpu_seconds_total".freeze
  DISK = "node_filesystem_avail_bytes".freeze

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!

    @region = regions(:regionone)
    # Derived, never hardcoded: the fixture endpoint renders DEV_VM_IP, so it is
    # 127.0.0.1 in CI and the dev VM's address on a workstation. A literal here
    # would pass in one place and hit a real Prometheus in the other.
    @endpoint = metric_clients(:vagrant_metric_client).endpoint
    @node = nodes(:testone) # hostname test01, active
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  # --- helpers ---------------------------------------------------------------

  # Match on the metric name inside the encoded query string. Metric names are
  # [A-Za-z_] so they survive URL encoding intact.
  # `node:` narrows the stub to one host. The metric name appears in the query
  # before the selector, so `fragment.*hostname` matches in that order.
  def stub_metric(fragment, result, node: nil, &body_block)
    suffix = node ? ".*#{node}" : ""
    url = %r{\A#{Regexp.escape(@endpoint)}/api/v1/query\?.*#{fragment}#{suffix}}
    stub = stub_request(:get, url)
    if body_block
      stub.to_return(&body_block)
    else
      stub.to_return(status: 200,
        headers: {"Content-Type" => "application/json"},
        body: prometheus_body(result))
    end
  end

  def prometheus_body(result)
    {status: "success", data: {resultType: "vector", result: result}}.to_json
  end

  def scalar_series(node, value)
    [{"metric" => {"node" => node}, "value" => [1_760_000_000, value.to_s]}]
  end

  def disk_series(node, by_mountpoint)
    by_mountpoint.map do |mountpoint, value|
      {"metric" => {"node" => node, "mountpoint" => mountpoint, "device" => "/dev/sda1"},
       "value" => [1_760_000_000, value.to_s]}
    end
  end

  # A second active node so the averaging path is actually exercised. after_create_commit
  # does not fire inside the test transaction, so no volume sync is triggered.
  def add_node(hostname, ip, active: true)
    Node.create!(label: hostname, hostname: hostname, primary_ip: ip, public_ip: ip,
      region: @region, active: active)
  end

  # --- the point of the change ----------------------------------------------

  test "the three reads for a node run concurrently rather than in sequence" do
    delay = 0.4
    [MEMORY, CPU, DISK].each do |fragment|
      stub_metric(fragment, nil) do
        sleep delay
        {status: 200, headers: {"Content-Type" => "application/json"},
         body: prometheus_body(scalar_series("test01", 10))}
      end
    end

    elapsed = Benchmark.realtime { @region.resource_usage }

    # Sequential would be ~3 * delay. Generous margin so this is not a flaky
    # timing test -- it only has to distinguish 0.4s from 1.2s.
    assert_operator elapsed, :<, delay * 2,
      "expected ~#{delay}s (concurrent), got #{elapsed.round(2)}s; sequential would be ~#{(delay * 3).round(2)}s"
  end

  # --- numbers must not move -------------------------------------------------

  test "averages the per-node readings across active nodes" do
    add_node("test02", "127.0.0.2")

    # DISTINCT values per node on purpose: stubbing both nodes alike would let
    # this test pass even if the per-node loop only ever read one of them.
    stub_metric(MEMORY, scalar_series("test01", 40.0), node: "test01")
    stub_metric(CPU, scalar_series("test01", 10.0), node: "test01")
    stub_metric(DISK, disk_series("test01", {"/" => 50.0}), node: "test01")
    stub_metric(MEMORY, scalar_series("test02", 60.0), node: "test02")
    stub_metric(CPU, scalar_series("test02", 20.0), node: "test02")
    stub_metric(DISK, disk_series("test02", {"/" => 70.0}), node: "test02")

    usage = @region.resource_usage

    assert_equal 15.0, usage[:cpu]     # (10 + 20) / 2
    assert_equal 50.0, usage[:memory]  # (40 + 60) / 2
    assert_equal 60.0, usage[:disk]    # (50 + 70) / 2
    assert_requested :get, %r{\A#{Regexp.escape(@endpoint)}/api/v1/query}, times: 6
  end

  test "prefers the /var/lib/docker filesystem over /" do
    stub_metric(MEMORY, scalar_series("test01", 40.0))
    stub_metric(CPU, scalar_series("test01", 10.0))
    stub_metric(DISK, disk_series("test01", {"/" => 50.0, "/var/lib/docker" => 88.0}))

    assert_equal 88.0, @region.resource_usage[:disk]
  end

  test "falls back to / when there is no /var/lib/docker filesystem" do
    stub_metric(MEMORY, scalar_series("test01", 40.0))
    stub_metric(CPU, scalar_series("test01", 10.0))
    stub_metric(DISK, disk_series("test01", {"/" => 61.5}))

    assert_equal 61.5, @region.resource_usage[:disk]
  end

  test "reports the region's container count" do
    stub_metric(MEMORY, scalar_series("test01", 40.0))
    stub_metric(CPU, scalar_series("test01", 10.0))
    stub_metric(DISK, disk_series("test01", {"/" => 50.0}))

    assert_equal @region.container_count, @region.resource_usage[:containers]
  end

  # --- degradation paths -----------------------------------------------------

  test "an inactive node is not read at all" do
    add_node("test02", "127.0.0.2", active: false)

    stub_metric(MEMORY, scalar_series("test01", 40.0))
    stub_metric(CPU, scalar_series("test01", 10.0))
    stub_metric(DISK, disk_series("test01", {"/" => 50.0}))

    @region.resource_usage

    # Three reads, for the one active node -- not six.
    assert_requested :get, %r{\A#{Regexp.escape(@endpoint)}/api/v1/query}, times: 3
    assert_not_requested :get, %r{test02}
  end

  test "one failing read does not take the other two down with it" do
    stub_metric(MEMORY, scalar_series("test01", 40.0))
    stub_metric(CPU, scalar_series("test01", 10.0))
    stub_metric(DISK, nil) { {status: 500, body: "boom"} }

    usage = @region.resource_usage

    # This isolation is why the three reads are separate requests rather than one
    # combined PromQL expression.
    assert_equal 10.0, usage[:cpu]
    assert_equal 40.0, usage[:memory]
    assert_equal 0.0, usage[:disk]
  end

  test "an empty result set degrades to zero rather than raising" do
    stub_metric(MEMORY, [])
    stub_metric(CPU, [])
    stub_metric(DISK, [])

    usage = @region.resource_usage

    assert_equal 0.0, usage[:cpu]
    assert_equal 0.0, usage[:memory]
    assert_equal 0.0, usage[:disk]
    assert_equal @region.container_count, usage[:containers]
  end

  test "a region with no active nodes reports zeroes without any HTTP call" do
    @node.update! active: false

    usage = @region.resource_usage

    assert_equal({cpu: 0.0, memory: 0.0, disk: 0.0, containers: @region.container_count}, usage)
    assert_not_requested :get, %r{/api/v1/query}
  end

  test "a region with no metric client reports zeroes without any HTTP call" do
    @region.update! metric_client: nil

    usage = @region.reload.resource_usage

    assert_equal({cpu: 0.0, memory: 0.0, disk: 0.0, containers: @region.container_count}, usage)
    assert_not_requested :get, %r{/api/v1/query}
  end
end
