require "test_helper"

class Nodes::CustomerStatusPresenterTest < ActiveSupport::TestCase
  P = Nodes::CustomerStatusPresenter

  setup do
    @node = nodes(:testone)
    @node.update_columns(active: true, disconnected: false, disconnected_at: nil, maintenance_requested: false,
      maintenance_holds: {}, maintenance_updated: nil, customer_notice: nil, online_at: 2.days.ago)
    @node.reload
    @region = @node.region
    @project = deployments(:project_test)
  end

  def add_node(hostname, ip, active: true, **cols)
    node = Node.create!(label: hostname, hostname: hostname, primary_ip: ip, public_ip: ip, region: @region, active: active)
    node.update_columns(cols) if cols.any?
    node.reload
  end

  def maintenance!(node, since: 1.hour.ago, notice: nil)
    node.update_columns(maintenance_requested: true, maintenance_updated: since, customer_notice: notice)
    node.reload
  end

  def offline!(node, since: 2.hours.ago, notice: nil)
    node.update_columns(disconnected: true, disconnected_at: since, customer_notice: notice)
    node.reload
  end

  def count_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE|ROLLBACK)/)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  # --- single node -----------------------------------------------------------------

  test "online node" do
    @node.update_columns(customer_notice: "left over")
    s = P.for_node(@node.reload)
    assert_equal "online", s["state"]
    assert_equal false, s["planned"]
    assert_nil s["message"], "a notice is never shown while online"
    assert_in_delta @node.online_at, s["since"], 1
    assert_equal P::OPERATIONS["online"], s["operations"]
    assert_equal %w[state since planned message operations], s.keys
  end

  test "maintenance node" do
    since = 30.minutes.ago
    maintenance!(@node, since: since, notice: "  Kernel upgrade  ")
    s = P.for_node(@node)
    assert_equal "maintenance", s["state"]
    assert_equal true, s["planned"]
    assert_equal "Kernel upgrade", s["message"]
    assert_in_delta since, s["since"], 1
    assert_equal "deferred", s["operations"]["power"]
    assert_equal "refused", s["operations"]["backup"]
    assert_equal "available", s["operations"]["config_changes"]
  end

  test "offline node" do
    since = 3.hours.ago
    offline!(@node, since: since, notice: "Hardware fault")
    s = P.for_node(@node)
    assert_equal "offline", s["state"]
    assert_equal false, s["planned"]
    assert_equal "Hardware fault", s["message"]
    assert_in_delta since, s["since"], 1
    assert_equal "refused", s["operations"]["power"]
    assert_equal "deferred", s["operations"]["config_changes"]
  end

  test "maintenance wins over disconnected (a rebooting node in maintenance is planned)" do
    maintenance!(@node)
    offline!(@node)
    assert_equal "maintenance", P.state_for(@node)
    assert_equal true, P.for_node(@node)["planned"]
  end

  test "a node-local hold is maintenance too" do
    @node.update_columns(maintenance_holds: {"local" => {"since" => 1, "reason" => "x"}})
    assert_equal "maintenance", P.state_for(@node.reload)
  end

  test "the active flag plays no part in a single node's state" do
    @node.update_columns(active: false)
    assert_equal "online", P.state_for(@node.reload)
  end

  test "a missing node is offline" do
    assert_equal "offline", P.state_for(nil)
    assert_equal "offline", P.for_node(nil)["state"]
  end

  test "codes" do
    assert_equal "node_maintenance", P.code_for("maintenance")
    assert_equal "node_offline", P.code_for("offline")
    assert_nil P.code_for("online")
  end

  test "operations table is frozen and complete" do
    assert P::OPERATIONS.frozen?
    assert_equal %w[online maintenance offline], P::OPERATIONS.keys
    P::OPERATIONS.each_value do |ops|
      assert ops.frozen?
      assert_equal %w[power backup restore export scale bastion_password_reset config_changes].sort, ops.keys.sort
    end
  end

  # --- rollup ----------------------------------------------------------------------

  test "rollup: worst wins, earliest since and first notice among the worst" do
    a = add_node("cs-a", "10.0.0.11")
    b = add_node("cs-b", "10.0.0.12")
    maintenance!(a, since: 5.hours.ago, notice: "maint")
    offline!(b, since: 1.hour.ago)
    offline!(@node, since: 2.hours.ago, notice: "down")
    s = P.rollup([a, b, @node])
    assert_equal "offline", s["state"]
    assert_in_delta 2.hours.ago, s["since"], 5
    assert_equal "down", s["message"]

    @node.update_columns(disconnected: false)
    s = P.rollup([a, @node.reload])
    assert_equal "maintenance", s["state"]
    assert_equal true, s["planned"]
    assert_equal "maint", s["message"]
  end

  test "rollup: all online has no message" do
    a = add_node("cs-a", "10.0.0.11", customer_notice: "stale")
    s = P.rollup([@node, a])
    assert_equal "online", s["state"]
    assert_nil s["message"]
  end

  test "rollup: empty set is offline" do
    assert_equal "offline", P.rollup([])["state"]
  end

  # --- region ----------------------------------------------------------------------

  test "region: inactive nodes hosting nothing are left out" do
    add_node("cs-inactive", "10.0.0.13", active: false, disconnected: true, disconnected_at: 1.hour.ago)
    assert_equal "online", P.for_region(@region.reload)["state"]
  end

  test "region: an inactive node still hosting containers counts" do
    @node.update_columns(active: false)
    assert_equal "online", P.for_region(@region.reload)["state"]
    offline!(@node)
    assert_equal "offline", P.for_region(Region.find(@region.id))["state"]
  end

  test "region: no active nodes and nothing hosted is offline" do
    Deployment::Container.where(node_id: @node.id).update_all(node_id: nil)
    Deployment::Sftp.where(node_id: @node.id).update_all(node_id: nil)
    @node.update_columns(active: false)
    assert_equal "offline", P.for_region(@region.reload)["state"]
  end

  # --- service ---------------------------------------------------------------------

  test "service: nodes hosting its containers, any active flag" do
    service = deployment_container_services(:pma)
    @node.update_columns(active: false, maintenance_requested: true)
    assert_equal "maintenance", P.for_service(service.reload)["state"]
  end

  test "service: no containers falls back to its region's active nodes" do
    service = deployment_container_services(:mysql)
    service.containers.update_all(container_service_id: deployment_container_services(:pma).id)
    inactive = add_node("cs-inactive", "10.0.0.13", active: false)
    offline!(inactive)
    assert_equal "online", P.for_service(service.reload)["state"]

    # @node is closed to placements but still hosts other containers, so it still counts.
    @node.update_columns(active: false)
    offline!(@node)
    assert_equal "offline", P.for_service(Deployment::ContainerService.find(service.id))["state"]
  end

  test "service: containers not placed on any node is offline" do
    service = deployment_container_services(:pma)
    service.containers.update_all(node_id: nil)
    assert_equal "offline", P.for_service(service.reload)["state"]
  end

  test "service: no queries when preloaded" do
    service = Deployment::ContainerService.preload(containers: :node, region: :nodes).find(deployment_container_services(:pma).id)
    assert_equal 0, count_queries { P.for_service(service) }
  end

  # --- project ---------------------------------------------------------------------

  test "project: includes its bastions' nodes" do
    bastion_node = add_node("cs-bastion", "10.0.0.14")
    @project.sftp_containers.first.update_columns(node_id: bastion_node.id)
    maintenance!(bastion_node, notice: "bastion node")
    s = P.for_project(@project.reload)
    assert_equal "maintenance", s["state"]
    assert_equal "bastion node", s["message"]
  end

  test "project: no placed containers falls back to its services' regions" do
    Deployment::Container.where(container_service_id: @project.services.select(:id)).update_all(node_id: nil)
    @project.sftp_containers.update_all(node_id: nil)
    assert_equal "online", P.for_project(@project.reload)["state"]
    offline!(@node)
    assert_equal "offline", P.for_project(Deployment.find(@project.id))["state"]
  end

  test "project: nothing at all is online" do
    empty = Deployment.create!(name: "empty", user: users(:admin))
    assert_empty empty.services
    assert_equal "online", P.for_project(empty)["state"]
  end

  test "project: no queries when preloaded" do
    project = Deployment.preload(services: [{containers: :node}, {region: :nodes}], sftp_containers: :node).find(@project.id)
    assert_equal 0, count_queries { P.for_project(project) }
  end
end
