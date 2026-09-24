require "test_helper"
require "webmock"
require "benchmark"

# Node.panel_metrics_for is what stops /admin/nodes issuing nine sequential
# Prometheus reads per node in the page request.
class NodePanelMetricsTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!

    @region = regions(:regionone)
    @endpoint = metric_clients(:vagrant_metric_client).endpoint
    @node = nodes(:testone)
    stub_any_query
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def stub_any_query(&body_block)
    stub = stub_request(:get, %r{\A#{Regexp.escape(@endpoint)}/api/v1/query})
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

  def loaded(*nodes)
    Node.where(id: nodes.map(&:id)).includes(:region, :metric_client).to_a
  end

  test "returns a hash of readings keyed by node id" do
    result = Node.panel_metrics_for(loaded(@node))

    assert_equal [@node.id], result.keys
    assert_equal Node::PANEL_READERS.keys.sort, result[@node.id].keys.sort
  end

  test "issues one read per metric per node and no more" do
    second = add_node("test02", "127.0.0.2")

    Node.panel_metrics_for(loaded(@node, second))

    # Five metrics, two nodes. The view used to cost nine per node because it
    # called the readers inline and repeatedly.
    assert_requested :get, %r{\A#{Regexp.escape(@endpoint)}/api/v1/query},
      times: Node::PANEL_READERS.size * 2
  end

  test "honours a metrics subset" do
    Node.panel_metrics_for(loaded(@node), metrics: %i[cpu memory])

    assert_requested :get, %r{\A#{Regexp.escape(@endpoint)}/api/v1/query}, times: 2
  end

  test "batches across nodes as well as across metrics" do
    add_node("test02", "127.0.0.2")
    add_node("test03", "127.0.0.3")
    WebMock.reset!
    delay = 0.3
    stub_any_query do
      sleep delay
      {status: 200, headers: {"Content-Type" => "application/json"}, body: ok_body}
    end

    nodes = Node.where(active: true).includes(:region, :metric_client).to_a
    assert_equal 3, nodes.size

    elapsed = Benchmark.realtime { Node.panel_metrics_for(nodes) }

    # 15 reads. Sequential would be ~4.5s; batched, and under the concurrency
    # cap of 12, this is two waves at most.
    assert_operator elapsed, :<, delay * 4,
      "expected roughly one or two waves, got #{elapsed.round(2)}s for 15 reads"
  end

  # Regression: Admin::NodesController#show passes a bare Node, and every read
  # thread then lazily loaded the same has_one-through, leasing a connection that
  # executor.wrap holds for the whole round trip. Five threads against a default
  # pool of five starves it, and the resulting ConnectionTimeoutError is
  # swallowed by each reader's own rescue -- a blank figure, no alert.
  test "no read thread touches the database, even for a node handed over unpreloaded" do
    bare = Node.find(@node.id) # no includes, exactly what load_node produces

    main = Thread.current
    from_threads = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if %w[SCHEMA TRANSACTION].include?(payload[:name].to_s)
      from_threads << payload[:sql] unless Thread.current == main
    end
    begin
      Node.panel_metrics_for([bare])
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    assert_empty from_threads,
      "reads must not query from a thread; got:\n#{from_threads.join("\n")}"
  end

  test "an empty node list does no work" do
    assert_equal({}, Node.panel_metrics_for([]))
    assert_not_requested :get, %r{/api/v1/query}
  end

  test "a node whose reads all fail still gets an entry" do
    WebMock.reset!
    stub_any_query { {status: 500, body: "boom"} }

    result = Node.panel_metrics_for(loaded(@node))

    # Every reader rescues internally, so the batch completes with neutral values.
    assert_equal [@node.id], result.keys
    assert_nil result[@node.id][:cpu]
    assert_equal [], result[@node.id][:disk]
  end
end
