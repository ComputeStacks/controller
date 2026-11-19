require "test_helper"
require "minitest/mock"

class Api::System::AlertNotificationsControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/system/alert_notifications"

  setup do
    @node = nodes(:testone)
    @node.update_columns(hostname: "node-a003", primary_ip: "10.99.0.9")
  end

  def alert(fingerprint, status: "firing", **labels)
    {
      fingerprint: fingerprint,
      status: status,
      labels: {alertname: "HighCpuLoad", severity: "warning", service: "container-node"}.merge(labels),
      annotations: {description: "CPU load is > 80%\n  VALUE = 91.2\n  LABELS: map[]"}
    }
  end

  def post_alerts(*alerts, status: "firing")
    post PATH, params: {receiver: "controller", status: status, alerts: alerts}, as: :json
    assert_response :success
  end

  test "each alert takes its own status, not the group's" do
    post_alerts alert("aaaa", instance: "10.99.0.9:9100"), alert("bbbb", instance: "10.99.0.4:9100")
    assert AlertNotification.find_by(fingerprint: "aaaa").active?

    # One recovered while the other still fires: the group status is still "firing".
    post_alerts alert("aaaa", status: "resolved", instance: "10.99.0.9:9100"), alert("bbbb", instance: "10.99.0.4:9100")

    assert AlertNotification.find_by(fingerprint: "aaaa").resolved?
    assert AlertNotification.find_by(fingerprint: "bbbb").active?
  end

  test "falls back to the group status when an alert has none" do
    post_alerts alert("aaaa").except(:status), status: "resolved"
    assert AlertNotification.find_by(fingerprint: "aaaa").resolved?
  end

  test "matches the node label case-insensitively" do
    post_alerts alert("aaaa", node: "Node-A003", instance: "10.9.9.9:9100")
    a = AlertNotification.find_by(fingerprint: "aaaa")
    assert_equal @node, a.node
    assert_empty a.labels
  end

  test "falls back to the instance address" do
    post_alerts alert("aaaa", instance: "10.99.0.9:9100")
    assert_equal @node, AlertNotification.find_by(fingerprint: "aaaa").node
  end

  test "keeps the raw labels when no node matches" do
    post_alerts alert("aaaa", node: "cs-controller", instance: "10.99.0.3:9100")
    a = AlertNotification.find_by(fingerprint: "aaaa")
    assert_nil a.node
    assert_equal({"node" => "cs-controller", "instance" => "10.99.0.3:9100"}, a.labels)
  end

  test "fills in a missing node on a later report" do
    post_alerts alert("aaaa", instance: "10.99.0.200:9100")
    assert_nil AlertNotification.find_by(fingerprint: "aaaa").node

    @node.update_columns(primary_ip: "10.99.0.200")
    post_alerts alert("aaaa", instance: "10.99.0.200:9100")

    a = AlertNotification.find_by(fingerprint: "aaaa")
    assert_equal @node, a.node
    assert_empty a.labels
  end

  test "container alerts never carry the raw host labels" do
    post_alerts alert("aaaa", name: "some-container", node: "cs-controller", instance: "10.99.0.3:8080")
    refute AlertNotification.find_by(fingerprint: "aaaa").labels.key?("instance")
  end

  test "a loopback instance does not match a node left on the default address" do
    @node.update_columns(primary_ip: "127.0.0.1")
    post_alerts alert("aaaa", instance: "127.0.0.1:9100")
    assert_nil AlertNotification.find_by(fingerprint: "aaaa").node
  end

  test "a resolved alert firing again counts and notifies, but not within 10 minutes" do
    post_alerts alert("aaaa", status: "resolved")
    a = AlertNotification.find_by(fingerprint: "aaaa")
    a.update_columns(last_event: 1.hour.ago)

    enqueued = []
    ProcessAlertWorker.stub(:perform_async, ->(id) { enqueued << id }) do
      post_alerts alert("aaaa")
      post_alerts alert("aaaa", status: "resolved")
      post_alerts alert("aaaa")
    end

    assert_equal [a.id], enqueued
    assert_equal 3, a.reload.event_count
    assert a.active?
  end

  test "a resolve batched with a firing alert notifies nothing" do
    post_alerts alert("aaaa"), alert("bbbb")
    enqueued = []
    ProcessAlertWorker.stub(:perform_async, ->(id) { enqueued << id }) do
      post_alerts alert("aaaa", status: "resolved"), alert("bbbb")
    end
    assert_empty enqueued
  end

  test "records when a firing alert was last reported" do
    post_alerts alert("aaaa")
    a = AlertNotification.find_by(fingerprint: "aaaa")
    a.update_columns(last_reported_at: 2.days.ago)

    post_alerts alert("aaaa")
    assert_in_delta Time.now, a.reload.last_reported_at, 5
  end
end
