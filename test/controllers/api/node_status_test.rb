require "test_helper"

# `node_status` on the customer API: present everywhere a customer can see a container,
# service, bastion, project or availability zone, correct for online / maintenance /
# offline, and preloaded on list endpoints so it adds no per-item node queries.
class Api::NodeStatusTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @node = nodes(:testone)
    @node.update_columns(active: true, disconnected: false, disconnected_at: nil, maintenance_requested: false,
      maintenance_holds: {}, maintenance_updated: nil, customer_notice: nil, online_at: 2.days.ago)
    @project = deployments(:project_test)
    @service = deployment_container_services(:wordpress)
    @container = deployment_containers(:wordpress_1)
    @bastion = deployment_sftp(:project_test_testone)
  end

  def maintenance!(node, notice: "Kernel upgrade")
    node.update_columns(maintenance_requested: true, maintenance_updated: 1.hour.ago, customer_notice: notice,
      maintenance_reason: "internal: swap the failing disk")
  end

  def offline!(node, notice: nil)
    node.update_columns(disconnected: true, disconnected_at: 2.hours.ago, customer_notice: notice)
  end

  def add_node(hostname, ip)
    Node.create!(label: hostname, hostname: hostname, primary_ip: ip, public_ip: ip, region: @node.region, active: true)
  end

  def get_json(path)
    get path, as: :json, headers: @basic_auth_headers
    assert_response :success
    JSON.parse(response.body)
  end

  # Every customer view of things on @node, keyed by where it came from.
  def statuses
    {
      "service show" => get_json("/api/container_services/#{@service.id}")["container_service"]["node_status"],
      "services index" => get_json("/api/container_services")["container_services"].find { |s| s["id"] == @service.id }["node_status"],
      "project services" => get_json("/api/projects/#{@project.id}/services")["container_services"].find { |s| s["id"] == @service.id }["node_status"],
      "container show" => get_json("/api/containers/#{@container.id}")["container"]["node_status"],
      "project containers" => get_json("/api/projects/#{@project.id}/containers")["containers"].find { |c| c["id"] == @container.id }["node_status"],
      "service containers" => get_json("/api/container_services/#{@service.id}/containers")["containers"].find { |c| c["id"] == @container.id }["node_status"],
      "project bastions" => get_json("/api/projects/#{@project.id}/bastions")["bastions"].find { |b| b["id"] == @bastion.id }["node_status"],
      "project bastion" => get_json("/api/projects/#{@project.id}/bastions/#{@bastion.id}")["bastion"]["node_status"],
      "service bastions" => get_json("/api/container_services/#{@service.id}/bastions")["bastions"].find { |b| b["id"] == @bastion.id }["node_status"],
      "service bastion" => get_json("/api/container_services/#{@service.id}/bastions/#{@bastion.id}")["bastion"]["node_status"],
      "project show" => get_json("/api/projects/#{@project.id}")["project"]["node_status"],
      "projects index" => get_json("/api/projects")["projects"].find { |p| p["id"] == @project.id }["node_status"],
      "locations index" => region_status(get_json("/api/locations")["locations"]),
      "location show" => region_status([get_json("/api/locations/#{@node.region.location_id}")["location"]])
    }
  end

  def region_status(locations)
    region = locations.flat_map { |l| l["regions"] }.find { |r| r["id"] == @node.region_id }
    region["node_status"]
  end

  def count_node_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      # Node records loaded; the service rabl's bastion lookup also joins nodes for ids
      # only, per service, which predates node_status and is not counted here.
      count += 1 if payload[:sql].match?(/\ASELECT "nodes"\.\* FROM "nodes"/)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  test "online everywhere" do
    statuses.each do |where, s|
      assert_equal "online", s["state"], where
      assert_equal false, s["planned"], where
      assert_nil s["message"], where
      assert_equal Nodes::CustomerStatusPresenter::OPERATIONS["online"], s["operations"], where
    end
  end

  test "maintenance everywhere, with the customer notice and never the internal reason" do
    maintenance!(@node)

    statuses.each do |where, s|
      assert_equal "maintenance", s["state"], where
      assert_equal true, s["planned"], where
      assert_equal "Kernel upgrade", s["message"], where
      assert s["since"].present?, where
      assert_equal "deferred", s["operations"]["power"], where
      assert_equal "refused", s["operations"]["backup"], where
    end
    get "/api/projects/#{@project.id}", as: :json, headers: @basic_auth_headers
    refute_includes response.body, "failing disk"
  end

  test "offline everywhere" do
    offline!(@node)

    statuses.each do |where, s|
      assert_equal "offline", s["state"], where
      assert_equal false, s["planned"], where
      assert_nil s["message"], where
      assert s["since"].present?, where
      assert_equal "refused", s["operations"]["power"], where
      assert_equal "deferred", s["operations"]["config_changes"], where
    end
  end

  test "rollups: worst state wins across nodes" do
    other = add_node("test02", "10.255.0.2")
    mysql = deployment_containers(:mysql_1)
    mysql.update_columns(node_id: other.id)
    maintenance!(other)

    # The service on the other node is in maintenance; wordpress is still online.
    mysql_service = get_json("/api/container_services/#{mysql.container_service_id}")["container_service"]["node_status"]
    assert_equal "maintenance", mysql_service["state"]
    assert_equal "online", get_json("/api/containers/#{@container.id}")["container"]["node_status"]["state"]
    assert_equal "maintenance", get_json("/api/projects/#{@project.id}")["project"]["node_status"]["state"]
    assert_equal "maintenance", region_status(get_json("/api/locations")["locations"])["state"]

    offline!(@node)
    project = get_json("/api/projects/#{@project.id}")["project"]["node_status"]
    assert_equal "offline", project["state"]
    assert_nil project["message"], "the notice belongs to the maintenance node, not the offline one"
  end

  test "an inactive node does not count toward its availability zone" do
    other = add_node("test02", "10.255.0.2")
    offline!(other)
    assert_equal "offline", region_status(get_json("/api/locations")["locations"])["state"]

    other.update_columns(active: false)
    assert_equal "online", region_status(get_json("/api/locations")["locations"])["state"]
  end

  test "xml responses carry node_status too" do
    maintenance!(@node)
    get "/api/containers/#{@container.id}", headers: @basic_auth_headers.merge("Accept" => "application/xml; api_version=65;")

    assert_response :success
    assert_match %r{<node-status>.*<state>maintenance</state>}m, response.body
  end

  test "list endpoints read nodes in a fixed number of queries, not one per item" do
    # A second availability zone with nodes, so /api/locations has more than one region.
    region = @node.region.dup
    region.name = "dev-two"
    region.save!(validate: false)
    Node.create!(label: "test03", hostname: "test03", primary_ip: "10.255.0.3", public_ip: "10.255.0.3", region: region, active: true)
    Node.create!(label: "test04", hostname: "test04", primary_ip: "10.255.0.4", public_ip: "10.255.0.4", region: region, active: true)

    {
      "/api/locations" => 1,
      "/api/projects/#{@project.id}/services" => 2, # container nodes + region nodes
      "/api/container_services" => 2,
      "/api/projects/#{@project.id}/containers" => 1,
      "/api/container_services/#{@service.id}/containers" => 1,
      "/api/projects/#{@project.id}/bastions" => 1,
      "/api/projects" => 3 # container nodes, region nodes, bastion nodes
    }.each do |path, max|
      queries = count_node_queries { get_json(path) }
      assert queries <= max, "#{path} read nodes #{queries} times (expected at most #{max})"
    end
  end

  test "admin views that reuse the service and container partials carry node_status" do
    maintenance!(@node)

    assert_equal "maintenance", get_json("/api/admin/container_services/#{@service.id}")["container_service"]["node_status"]["state"]
    listed = get_json("/api/admin/container_services?all=true")["container_services"].find { |s| s["id"] == @service.id }
    assert_equal "maintenance", listed["node_status"]["state"]

    subscription = @container.subscription
    assert subscription, "fixture container should have a subscription"
    assert_equal "maintenance", get_json("/api/admin/subscriptions/#{subscription.id}")["subscription"]["container"]["node_status"]["state"]
  end
end
