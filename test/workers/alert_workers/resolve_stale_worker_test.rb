require "test_helper"

class AlertWorkers::ResolveStaleWorkerTest < ActiveSupport::TestCase
  def create_alert(fingerprint, status: "firing", **attrs)
    AlertNotification.create!(fingerprint: fingerprint, name: "HighCpuLoad", severity: "warning",
      status: status, last_event: 1.day.ago, **attrs)
  end

  test "resolves firing alerts no longer reported" do
    stale = create_alert("stale", last_reported_at: 7.hours.ago)
    fresh = create_alert("fresh", last_reported_at: 1.hour.ago)

    AlertWorkers::ResolveStaleWorker.new.perform

    assert stale.reload.resolved?
    assert fresh.reload.active?
  end

  test "leaves resolved alerts alone" do
    done = create_alert("done", status: "resolved", last_reported_at: 3.days.ago)
    done.update_columns(updated_at: 3.days.ago)

    AlertWorkers::ResolveStaleWorker.new.perform

    assert_in_delta 3.days.ago, done.reload.updated_at, 5
  end

  test "a firing alert without last_reported_at falls back to updated_at" do
    old = create_alert("old")
    old.update_columns(updated_at: 8.days.ago)
    recent = create_alert("recent")

    AlertWorkers::ResolveStaleWorker.new.perform

    assert old.reload.resolved?
    assert recent.reload.active?
  end
end
