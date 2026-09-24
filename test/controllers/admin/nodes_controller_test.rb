require "test_helper"
require "webmock"
require "benchmark"

# /admin/nodes renders every node in the fleet in one synchronous request, and
# the panel partial used to call its Prometheus readers inline -- nine reads per
# node, in sequence, blocking the response. These tests pin the read count and
# the concurrency, because neither is visible from the rendered HTML.
class Admin::NodesControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers
  include WebMock::API

  READS_PER_NODE = 5 # Node::PANEL_READERS.size

  setup do
    sign_in users(:admin)
    @region = regions(:regionone)
    @node = nodes(:testone)
    @endpoint = metric_clients(:vagrant_metric_client).endpoint
    WebMock.enable!
    WebMock.disable_net_connect!
    stub_any_query
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def query_pattern
    %r{\A#{Regexp.escape(@endpoint)}/api/v1/query}
  end

  def stub_any_query(&body_block)
    stub = stub_request(:get, query_pattern)
    if body_block
      stub.to_return(&body_block)
    else
      stub.to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: ok_body)
    end
  end

  def ok_body
    {status: "success",
     data: {resultType: "vector",
            result: [{"metric" => {"node" => "test01", "mountpoint" => "/", "device" => "/dev/sda1"},
                      "value" => [1_760_000_000, "42"]}]}}.to_json
  end

  def add_node(hostname, ip)
    Node.create!(label: hostname, hostname: hostname, primary_ip: ip, public_ip: ip,
      region: @region, active: true)
  end

  test "index renders" do
    get "/admin/nodes"

    assert_response :success
    assert_match @node.label, response.body
    assert_match "CPU", response.body
  end

  test "index issues one read per metric per node and no more" do
    add_node("test02", "127.0.0.2")

    get "/admin/nodes"

    assert_response :success
    assert_requested :get, query_pattern, times: READS_PER_NODE * 2
  end

  test "index fetches every node's metrics in one concurrent batch" do
    add_node("test02", "127.0.0.2")
    add_node("test03", "127.0.0.3")
    WebMock.reset!

    # Measure CONCURRENCY, not elapsed time. This used to assert the request finished
    # inside a wall-clock budget, which passes in a quiet process and fails on a busy
    # one -- a test that fails once and then hides, and one that would fail the build on
    # a loaded CI runner rather than on anything to do with the code.
    #
    # Counting how many stubbed reads are in flight at once answers the actual question:
    # 15 reads issued sequentially never exceed a peak of 1.
    lock = Mutex.new
    in_flight = 0
    peak = 0
    stub_any_query do
      lock.synchronize do
        in_flight += 1
        peak = in_flight if in_flight > peak
      end
      sleep 0.05
      lock.synchronize { in_flight -= 1 }
      {status: 200, headers: {"Content-Type" => "application/json"}, body: ok_body}
    end

    get "/admin/nodes"

    assert_response :success
    assert_requested :get, query_pattern, times: READS_PER_NODE * 3
    assert_operator peak, :>, 1,
      "#{READS_PER_NODE * 3} reads never overlapped -- they were issued sequentially"
  end

  test "the per-node xhr panel reads only that node" do
    add_node("test02", "127.0.0.2")

    get "/admin/nodes/#{@node.id}", xhr: true

    assert_response :success
    assert_no_match(/<html/, response.body) # layout: false
    assert_requested :get, query_pattern, times: READS_PER_NODE
  end

  test "a zone's node list renders over xhr" do
    get "/admin/regions/#{@region.id}/nodes", xhr: true

    assert_response :success
    assert_match @node.label, response.body
    assert_requested :get, query_pattern, times: READS_PER_NODE
  end

  # Persisted capacity has to be VISIBLE. Unknown capacity now fails open at placement
  # time, so a node whose Docker.info quietly never succeeds behaves like a healthy one;
  # the panel is the only place an operator would notice.
  test "the panel shows the persisted capacity and when it was last refreshed" do
    @node.update_columns(cpu_cores: 48, memory_mb: 8192, capacity_updated_at: 3.minutes.ago)

    get "/admin/nodes"

    assert_response :success
    assert_match "48 cores", response.body
    assert_match "3 minutes ago", response.body
    # A stored fact, not a metrics read -- the panel's Prometheus budget is unchanged.
    assert_requested :get, query_pattern, times: READS_PER_NODE
  end

  test "the panel says so when a node has never reported its capacity" do
    assert_nil @node.cpu_cores

    get "/admin/nodes"

    assert_response :success
    assert_match "unknown", response.body
    assert_match "never", response.body
  end

  test "a node whose reads all fail still renders" do
    WebMock.reset!
    stub_any_query { {status: 500, body: "boom"} }

    get "/admin/nodes"

    assert_response :success
    assert_match @node.label, response.body
  end
end
