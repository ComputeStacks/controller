require "test_helper"

class EventLog::AdminFilterTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @node_offline = EventLog.create!(locale: "node.offline", status: "completed", event_code: "aaaa111122223333")
    @node_ports = EventLog.create!(locale: "node.ports.open", status: "failed", created_at: 3.days.ago)
    @volume = EventLog.create!(locale: "volume.backup", status: "running", created_at: 40.days.ago,
      audit: Audit.create!(user: @user, event: "updated"))
    @scope = EventLog.where(id: [@node_offline, @node_ports, @volume].map(&:id))
  end

  def filtered(params)
    EventLog::AdminFilter.new(params).apply(@scope).to_a
  end

  test "no params returns everything" do
    assert_equal 3, filtered({}).size
  end

  test "status" do
    assert_equal [@node_ports], filtered(status: "failed")
    assert_equal [@volume], filtered(status: "active")
  end

  test "exact kinds and families" do
    assert_equal [@node_offline], filtered(kind: ["node.offline"])
    assert_equal [@node_offline, @node_ports].sort, filtered(kind: ["node.*"]).sort
    assert_equal [@node_ports, @volume].sort, filtered(kind: ["backup.*", "node.ports.open"]).sort
  end

  test "backup kinds are grouped together, wherever their locale lives" do
    assert_equal %w[backup.delete backup.sync_volumes volume.backup volume.download volume.restore],
      EventLog::AdminFilter.kind_groups["backup"].map(&:first).sort
    refute_includes EventLog::AdminFilter.kind_groups["volume"].map(&:first), "volume.backup"
    delete = EventLog.create!(locale: "backup.delete", status: "completed")
    vol_delete = EventLog.create!(locale: "volume.delete", status: "completed")
    scope = EventLog.where(id: [@volume, delete, vol_delete].map(&:id))
    assert_equal [@volume, delete].sort, EventLog::AdminFilter.new(kind: ["backup.*"]).apply(scope).to_a.sort
    assert_equal [vol_delete], EventLog::AdminFilter.new(kind: ["volume.*"]).apply(scope).to_a
  end

  test "family wildcard does not leak LIKE metacharacters" do
    assert_empty filtered(kind: ["%.*"])
  end

  test "period" do
    assert_equal [@node_offline], filtered(period: "24h")
    assert_equal [@node_offline, @node_ports].sort, filtered(period: "7d").sort
  end

  test "date range is inclusive of both days and tolerates reversed input" do
    day = 3.days.ago.to_date
    assert_equal [@node_ports], filtered(timerange: "#{day} - #{day}")
    assert_equal [@node_ports], filtered(timerange: "#{day + 1} - #{day - 1}")
  end

  test "a custom range overrides the preset period" do
    day = 3.days.ago.to_date
    assert_equal [@node_ports], filtered(period: "24h", timerange: "#{day} - #{day}")
  end

  test "a family also matches its bare key" do
    unknown = EventLog.create!(locale: "unknown", status: "completed")
    assert_equal [unknown], EventLog::AdminFilter.new(kind: ["unknown.*"]).apply(EventLog.where(id: unknown.id)).to_a
  end

  test "odd param shapes do not raise" do
    assert_empty filtered(kind: {"a" => "b"})
    assert_equal [@node_offline], filtered(kind: "node.offline")
    assert_empty filtered(performed_by: "abc")
  end

  test "invalid date range is ignored and reported" do
    filter = EventLog::AdminFilter.new(timerange: "yesterday")
    assert filter.invalid_range?
    assert_equal 3, filter.apply(@scope).count
  end

  test "performed by" do
    assert_equal [@volume], filtered(performed_by: "user")
    assert_equal [@volume], filtered(performed_by: @user.id.to_s)
    assert_equal [@node_offline, @node_ports].sort, filtered(performed_by: "system").sort
  end

  test "with details and with system errors" do
    @node_ports.event_details.create!(data: "boom", event_code: "bbbb111122223333")
    SystemEvent.create!(message: "oops", audit: @volume.audit, event_code: "cccc111122223333")

    assert_equal [@node_ports], filtered(with_details: "1")
    assert_equal [@volume], filtered(with_system_events: "1")
  end

  test "event code matches the log, its details, or its system events" do
    @node_ports.event_details.create!(data: "boom", event_code: "bbbb111122223333")
    SystemEvent.create!(message: "oops", audit: @volume.audit, event_code: "cccc111122223333")

    assert_equal [@node_offline], filtered(code: " aaaa111122223333 ")
    assert_equal [@node_ports], filtered(code: "bbbb111122223333")
    assert_equal [@volume], filtered(code: "cccc111122223333")
  end

  test "kind catalog is grouped by family" do
    groups = EventLog::AdminFilter.kind_groups
    assert_includes groups["node"].map(&:first), "node.ports.open"
    refute groups.values.flatten.any? { |s| s.include?("%{") }
  end
end
