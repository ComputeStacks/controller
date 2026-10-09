require "test_helper"

class Nodes::MaintenanceStatusPresenterTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    @node.update_columns(
      maintenance_requested: false, maintenance_reason: nil, maintenance_gen: 0,
      maintenance_override_gen: nil, maintenance_holds: {}, maintenance_status: {},
      agent_maintenance_unsupported_at: nil, agent_instance_id: nil
    )
    @node.reload
  end

  def presenter
    Nodes::MaintenanceStatusPresenter.new(@node.reload)
  end

  def local_hold(since: 1.hour.ago, reason: "docker-upgrade")
    {"since" => since.utc.iso8601, "reason" => reason, "by" => "root"}
  end

  test "a node out of maintenance renders a complete, quiet status object" do
    json = presenter.as_json

    assert_equal %w[effective requested reason requested_at gen holds paused_since skipped_backups sample agent running pending warnings].sort,
      json.keys.sort
    assert_equal false, json["effective"]
    assert_equal false, json["requested"]
    assert_nil json["requested_at"]
    assert_equal({"controller" => nil, "local" => nil}, json["holds"])
    assert_nil json["sample"]
    assert_equal [], json["running"]
    assert_equal 0, json["skipped_backups"]
    assert_equal true, json["agent"]["supported"]
    assert_equal [], json["warnings"]
    assert_nil presenter.held_by_text
    assert_nil presenter.quiesce_text
  end

  test "a controller hold confirmed by the agent" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel", maintenance_gen: 4,
      maintenance_updated: 5.minutes.ago,
      maintenance_holds: {"controller" => {"since" => 5.minutes.ago.utc.iso8601, "reason" => "kernel", "gen" => 4},
                          "local" => nil, "paused_since" => 5.minutes.ago.utc.iso8601, "skipped_backups" => 2,
                          "sample" => {"quiesce" => "busy", "running_count" => 2, "pending" => 1, "sampled_at" => 1.minute.ago.utc.iso8601}},
      maintenance_status: {"observed_at" => 1.minute.ago.utc.iso8601, "running" => [{"id" => 1, "kind" => "backup"}], "pending" => 1, "quiesce" => "busy"})
    p = presenter
    json = p.as_json

    assert_equal true, json["effective"]
    assert_equal true, json["requested"]
    assert_equal "kernel", json["reason"]
    assert_equal 4, json["gen"]
    assert_equal 4, json["holds"]["controller"]["gen"]
    assert_nil json["holds"]["local"]
    assert_equal 2, json["skipped_backups"]
    assert_equal "busy", json["sample"]["quiesce"]
    assert_equal 1, json["running"].size
    assert_equal 1, json["pending"]
    assert_equal [], json["warnings"]

    assert_match(/\Aheld by controller \(kernel\), since \d\d:\d\d UTC\z/, p.held_by_text)
    assert_match(/\AQuiescing: 2 running \(1 minute ago\)\z/, p.quiesce_text)
    assert_equal "In Maintenance (controller)", p.state_text
  end

  test "a node-only hold, quiesced" do
    @node.update_columns(maintenance_holds: {"controller" => nil, "local" => local_hold, "paused_since" => 1.hour.ago.utc.iso8601,
                                             "sample" => {"quiesce" => "quiesced", "running_count" => 0, "sampled_at" => Time.now.utc.iso8601}},
      maintenance_status: {"observed_at" => Time.now.utc.iso8601})
    p = presenter

    assert p.effective?
    assert_equal ["node"], p.held_by
    assert p.quiesced?
    assert_match(/\Aheld by node \(docker-upgrade\), since/, p.held_by_text)
    assert_match(/\AQuiesced/, p.quiesce_text)
  end

  test "held by both names both reasons" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel",
      maintenance_holds: {"local" => local_hold}, maintenance_status: {"observed_at" => Time.now.utc.iso8601})

    assert_match(/\Aheld by controller \(kernel\) and node \(docker-upgrade\)/, presenter.held_by_text)
    assert_equal "In Maintenance (controller + node)", presenter.state_text
  end

  test "a hold older than 12 hours is flagged" do
    @node.update_columns(maintenance_holds: {"local" => local_hold(since: 13.hours.ago), "paused_since" => 13.hours.ago.utc.iso8601},
      maintenance_status: {"observed_at" => Time.now.utc.iso8601})

    assert_equal ["stale_hold"], presenter.warnings
  end

  test "a since older than a day carries its date" do
    @node.update_columns(maintenance_holds: {"local" => local_hold(since: 30.hours.ago), "paused_since" => 30.hours.ago.utc.iso8601})

    assert_match(/since [A-Z][a-z]{2} \d+ \d\d:\d\d UTC\z/, presenter.held_by_text)
  end

  test "mismatch comes from the drift worker's mismatch_since" do
    @node.update_columns(maintenance_status: {"observed_at" => Time.now.utc.iso8601, "mismatch_since" => 5.minutes.ago.utc.iso8601})

    assert_includes presenter.warnings, "mismatch"
  end

  test "status_stale while in maintenance and the agent has not been heard from" do
    @node.update_columns(maintenance_requested: true, maintenance_status: {"observed_at" => 30.minutes.ago.utc.iso8601})
    assert_includes presenter.warnings, "status_stale"

    @node.update_columns(maintenance_status: {})
    assert_includes presenter.warnings, "status_stale"

    # Out of maintenance a stale status says nothing worth a badge.
    @node.update_columns(maintenance_requested: false)
    assert_empty presenter.warnings
  end

  test "unsupported_agent only while the controller is asking for a hold" do
    @node.update_columns(agent_maintenance_unsupported_at: 10.minutes.ago)
    refute_includes presenter.warnings, "unsupported_agent"
    assert_equal false, presenter.as_json["agent"]["supported"]

    @node.update_columns(maintenance_requested: true)
    assert_includes presenter.warnings, "unsupported_agent"
    refute_includes presenter.warnings, "status_stale", "no point calling an agent that cannot answer stale"

    # A later successful observation clears it.
    @node.update_columns(maintenance_status: {"observed_at" => Time.now.utc.iso8601})
    refute_includes presenter.warnings, "unsupported_agent"
  end

  test "override_pending until the override generation is cleared" do
    @node.update_columns(maintenance_gen: 5, maintenance_override_gen: 5)

    assert_includes presenter.warnings, "override_pending"
  end

  test "summary counts only columns and lists nodes in maintenance" do
    other = Node.create!(label: "test02", hostname: "test02", primary_ip: "127.0.0.2", public_ip: "127.0.0.2",
      region: @node.region, active: true)
    other.update_columns(maintenance_holds: {"local" => local_hold, "sample" => {"quiesce" => "quiesced"}},
      maintenance_status: {"observed_at" => Time.now.utc.iso8601})

    summary = Nodes::MaintenanceStatusPresenter.summary(@node.region.nodes)

    assert_equal 2, summary["nodes_total"]
    assert_equal 1, summary["nodes_in_maintenance"]
    assert_equal 1, summary["nodes_quiesced"]
    assert_equal 0, summary["nodes_with_warnings"]
    assert_equal [{"id" => other.id, "label" => "test02", "held_by" => ["node"], "since" => other.reload.maintenance_since}],
      summary["nodes"]

    with_region = Nodes::MaintenanceStatusPresenter.summary(@node.region.nodes, include_region: true)
    assert_equal @node.region_id, with_region["nodes"].first["region_id"]
  end

  test "pending_agent_syncs counts live and dead rows separately" do
    region = @node.region
    assert_equal({"pending" => 0, "dead" => 0, "oldest_at" => nil},
      Nodes::MaintenanceStatusPresenter.pending_agent_syncs([region.id]))

    oldest = 3.hours.ago.change(usec: 0)
    AgentPendingSync.create!(region: region, project_id: 1, kind: "managed_metadata", first_failed_at: oldest)
    AgentPendingSync.create!(region: region, project_id: 2, kind: "tenant", first_failed_at: 1.hour.ago)
    AgentPendingSync.create!(region: region, node: @node, kind: "firewall", first_failed_at: 5.days.ago, dead_at: 1.day.ago)

    result = Nodes::MaintenanceStatusPresenter.pending_agent_syncs([region.id])
    assert_equal 2, result["pending"]
    assert_equal 1, result["dead"]
    assert_equal oldest, result["oldest_at"], "a dead row is not the oldest pending one"
  end

  test "the agent's unix-second timestamps are understood" do
    paused = 2.hours.ago.to_i
    @node.update_columns(maintenance_holds: {"local" => {"since" => paused, "reason" => "upgrade", "by" => "root"},
                                             "paused_since" => paused,
                                             "sample" => {"quiesce" => "busy", "running_count" => 1, "sampled_at" => 3.minutes.ago.to_i}},
      maintenance_status: {"observed_at" => Time.now.utc.iso8601})
    p = presenter

    assert_equal Time.at(paused).utc, p.as_json["paused_since"]
    assert_equal Time.at(paused).utc.strftime("%H:%M UTC"), p.hold_since_text(@node.maintenance_local_hold)
    assert_match(/\AQuiescing: 1 running \(3 minutes ago\)\z/, p.quiesce_text)
    assert_equal Time.at(paused).utc, p.send(:parse_time, paused.to_s)
  end
end
