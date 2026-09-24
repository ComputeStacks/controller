require "test_helper"

##
# Backup export / download behaviour on Volume. The presigned URL now comes from the
# correlated `backup.export` task's projected result (agent_tasks.result), not Consul —
# correlated via the export EventLog's `task_id` label.
class VolumeExportTest < ActiveSupport::TestCase
  setup do
    @volume = volumes(:mysql)
    @volume.event_logs.delete_all
    @node = nodes(:testone)
  end

  def export_event(status:, archive:, task_id: nil, created_at: nil)
    labels = {"archive" => archive}
    labels["task_id"] = task_id if task_id
    @volume.event_logs.create!(
      locale: "volume.download",
      locale_keys: {},
      status: status,
      event_code: EventLog::BACKUP_EXPORT_EVENT_CODE,
      labels: labels,
      created_at: created_at || Time.now
    )
  end

  def export_task(id:, status:, result: nil)
    AgentTask.create!(id: id, name: "backup.export", status: status, volume: @volume.name,
      node_id: @node.id, result: result)
  end

  # --- non-blocking event handling -------------------------------------------

  test "non_blocking_codes includes the backup export code" do
    assert_includes EventLog.non_blocking_codes, EventLog::BACKUP_EXPORT_EVENT_CODE
  end

  test "a running export does not count as an operation in progress" do
    export_event(status: "running", archive: "arch1", task_id: "jid1")
    refute @volume.operation_in_progress?, "export should not block backups/restores"
  end

  test "a running non-export event still counts as an operation in progress" do
    @volume.event_logs.create!(
      locale: "volume.backup",
      locale_keys: {},
      status: "running",
      event_code: "agent-ad28e9aa1933495f"
    )
    assert @volume.operation_in_progress?
  end

  # --- export_status_map (join events + projected task result) ---------------

  test "status map reports in_progress for an active export" do
    export_event(status: "running", archive: "arch1", task_id: "jid1")
    assert_equal "in_progress", @volume.export_status_map["arch1"][:status]
  end

  test "status map reports ready with url for a completed, unexpired https export" do
    export_event(status: "completed", archive: "arch1", task_id: "jid1")
    export_task(id: "jid1", status: "completed",
      result: {"url" => "https://dl/x.tar", "expiry" => 1.hour.from_now.to_i, "size" => 42})
    state = @volume.export_status_map["arch1"]
    assert_equal "ready", state[:status]
    assert_equal "https://dl/x.tar", state[:url]
    assert_equal 42, state[:size]
  end

  test "status map reports expired for a past-expiry result" do
    export_event(status: "completed", archive: "arch1", task_id: "jid1")
    export_task(id: "jid1", status: "completed",
      result: {"url" => "https://dl/x.tar", "expiry" => 1.hour.ago.to_i})
    assert_equal "expired", @volume.export_status_map["arch1"][:status]
  end

  test "status map never reports ready for a non-https url" do
    export_event(status: "completed", archive: "arch1", task_id: "jid1")
    export_task(id: "jid1", status: "completed",
      result: {"url" => "http://dl/x.tar", "expiry" => 1.hour.from_now.to_i})
    assert_equal "expired", @volume.export_status_map["arch1"][:status]
  end

  test "status map never reports ready when the task_id label is missing" do
    export_event(status: "completed", archive: "arch1", task_id: nil)
    assert_equal "expired", @volume.export_status_map["arch1"][:status]
  end

  test "status map never reports ready when the correlated task is missing" do
    export_event(status: "completed", archive: "arch1", task_id: "gone")
    assert_equal "expired", @volume.export_status_map["arch1"][:status]
  end

  test "status map reports failed and surfaces the reason" do
    e = export_event(status: "failed", archive: "arch1")
    e.update_column(:state_reason, "boom")
    state = @volume.export_status_map["arch1"]
    assert_equal "failed", state[:status]
    assert_equal "boom", state[:error]
  end

  test "status map uses the most recent event per archive" do
    export_event(status: "completed", archive: "arch1", task_id: "old", created_at: 2.hours.ago)
    export_event(status: "failed", archive: "arch1", created_at: 1.hour.ago)
    assert_equal "failed", @volume.export_status_map["arch1"][:status]
  end

  # --- enqueue guard ---------------------------------------------------------

  test "export_backup! refuses a blank archive name" do
    refute @volume.export_backup!("")
  end
end
