require "test_helper"
require "minitest/mock"
require "webmock"

class Agent::TaskReconcilerTest < ActiveSupport::TestCase
  BACKUP_CODE = "agent-ad28e9aa1933495f".freeze

  setup do
    CallbackWorker.clear
    @volume = volumes(:mysql)
    @node = nodes(:testone)
  end

  def make_task(id: "t1", name: "volume.backup", status: "pending", audit_id: nil,
    volume: @volume.name, reconciled_status: nil, result: nil)
    AgentTask.create!(id: id, name: name, status: status, audit_id: audit_id, volume: volume,
      node_id: @node.id, project_id: @volume.deployment&.id.to_s, reconciled_status: reconciled_status,
      result: result)
  end

  def make_audit
    Audit.create!(event: "backup.create", rel_id: @volume.id, rel_model: "Volume")
  end

  def precreate_event(audit:, code: BACKUP_CODE, callback: false)
    event = EventLog.new(locale: "volume.backup", locale_keys: {}, status: "pending", audit: audit, event_code: code)
    event.labels = {"callback_url" => "https://cb.example/hook", "callback_auth" => "Bearer x"} if callback
    event.volumes << @volume
    event.deployments << @volume.deployment if @volume.deployment
    event.save!
    event
  end

  test "drives a pre-created event pending -> running -> completed across passes" do
    audit = make_audit
    event = precreate_event(audit: audit)
    task = make_task(audit_id: audit.id, status: "running")

    Agent::TaskReconciler.new.call
    assert event.reload.running?
    assert_equal "running", task.reload.reconciled_status

    task.update!(status: "completed")
    Agent::TaskReconciler.new.call
    assert event.reload.success?
    assert_equal "completed", task.reload.reconciled_status
  end

  test "fires the completion callback exactly once across duplicate passes" do
    audit = make_audit
    event = precreate_event(audit: audit, callback: true)
    make_task(audit_id: audit.id, status: "completed")

    Agent::TaskReconciler.new.call
    Agent::TaskReconciler.new.call # second pass: needs_reconcile now excludes it

    assert event.reload.success?
    assert_equal 1, CallbackWorker.jobs.size
  end

  test "creates the event and an auto-Audit for an agent-originated task with no audit_id" do
    task = make_task(id: "sched1", status: "completed", audit_id: nil)
    assert_difference ["Audit.count", "EventLog.count"], 1 do
      Agent::TaskReconciler.new.call
    end
    event = EventLog.where(event_code: BACKUP_CODE).order(:created_at).last
    assert event.success?
    assert_includes event.volumes, @volume
    assert_equal "completed", task.reload.reconciled_status
  end

  # callback: true is load-bearing — without it perform_callback_reply! short-circuits on the
  # missing callback_url and nothing here proves a genuine failure still DELIVERS. The whole
  # point of the deferred enqueue is to stop emitting spurious `success: false`, so we need
  # the counterweight: real failures must still report.
  test "drives a failed task to fail! with the result output as the reason, and still delivers the callback" do
    audit = make_audit
    event = precreate_event(audit: audit, callback: true)
    make_task(audit_id: audit.id, status: "failed", result: {"output" => "borg blew up"})

    Agent::TaskReconciler.new.call
    assert event.reload.failed?
    assert_equal "borg blew up", event.state_reason
    assert_equal 1, CallbackWorker.jobs.size, "a genuine failure must still fire its callback"
  end

  test "records a result-summary event_detail on a completed backup" do
    audit = make_audit
    event = precreate_event(audit: audit)
    make_task(audit_id: audit.id, status: "completed", result: {"last_backup" => 1_700_000_000})

    Agent::TaskReconciler.new.call
    assert event.reload.success?
    detail = event.event_details.last
    assert_not_nil detail
    assert_includes detail.data, "Last backup:"
  end

  test "records no result detail when the completed result has no structured fields" do
    audit = make_audit
    event = precreate_event(audit: audit)
    make_task(audit_id: audit.id, status: "completed", result: {})

    Agent::TaskReconciler.new.call
    assert event.reload.success?
    assert_equal 0, event.event_details.count
  end

  test "heartbeat touches the correlated event of an active task so StaleEventWorker skips it" do
    audit = make_audit
    event = precreate_event(audit: audit)
    event.update_columns(status: "running", updated_at: 2.hours.ago)
    # already reconciled to running, so only the heartbeat (not a transition) should run
    make_task(audit_id: audit.id, status: "running", reconciled_status: "running")

    Agent::TaskReconciler.new.call
    assert event.reload.updated_at > 1.hour.ago
    assert_equal "running", event.status
  end

  test "does nothing when already reconciled to the current status" do
    audit = make_audit
    event = precreate_event(audit: audit, callback: true)
    event.update_columns(status: "completed")
    make_task(audit_id: audit.id, status: "completed", reconciled_status: "completed")

    Agent::TaskReconciler.new.call
    assert_equal 0, CallbackWorker.jobs.size
    assert event.reload.success?
  end

  test "re-issues a failed volume.trash DELETE, bounded by reissue_count" do
    task = AgentTask.create!(id: "volume.trash:vol-x", name: "volume.trash", status: "failed",
      volume: "vol-x", node_id: @node.id, project_id: "0", reconciled_status: "failed")

    client = Minitest::Mock.new
    client.expect(:delete_volume, true, ["0", "vol-x"])
    Agent::Client.stub(:for_node, client) do
      Agent::TaskReconciler.new.call
    end
    client.verify
    assert_equal 1, task.reload.reissue_count

    # at the cap, no further DELETE is issued
    task.update_columns(reissue_count: Agent::TaskReconciler::MAX_TEARDOWN_REISSUES)
    capped = Minitest::Mock.new # no expectations → any call fails verify
    Agent::Client.stub(:for_node, capped) do
      Agent::TaskReconciler.new.call
    end
    assert_equal Agent::TaskReconciler::MAX_TEARDOWN_REISSUES, task.reload.reissue_count
  end

  test "surfaces a failed volume.trash as a SystemEvent and advances reconciled" do
    task = make_task(id: "volume.trash:#{@volume.name}", name: "volume.trash", status: "failed",
      result: {"output" => "repo locked"})
    assert_difference "SystemEvent.count", 1 do
      Agent::TaskReconciler.new.call
    end
    assert_equal "failed", task.reload.reconciled_status
  end

  test "advances reconciled even when the volume can't be resolved (no event created)" do
    task = make_task(id: "orphan", status: "completed", audit_id: nil, volume: "no-such-volume")
    assert_no_difference "EventLog.count" do
      Agent::TaskReconciler.new.call
    end
    assert_equal "completed", task.reload.reconciled_status
  end

  test "an agent-originated task is driven through ONE event across transitions" do
    task = make_task(id: "sched2", status: "pending", audit_id: nil)
    assert_difference ["EventLog.count", "Audit.count"], 1 do
      Agent::TaskReconciler.new.call # pending -> create event
      task.update!(status: "running")
      Agent::TaskReconciler.new.call # running
      task.update!(status: "completed")
      Agent::TaskReconciler.new.call # completed
    end
    event = EventLog.where("labels ->> 'task_id' = ?", "sched2").first
    assert_not_nil event
    assert event.success?
  end

  test "heartbeat protects an agent-originated (audit-less) task's event from StaleEventWorker" do
    task = make_task(id: "sched3", status: "running", audit_id: nil)
    Agent::TaskReconciler.new.call
    event = EventLog.where("labels ->> 'task_id' = ?", "sched3").first
    assert event.running?

    event.update_columns(updated_at: 2.hours.ago)
    Agent::TaskReconciler.new.call # reconciled==running, so only the heartbeat runs
    assert event.reload.updated_at > 1.hour.ago
  end

  test "does not heartbeat when the node is offline (dead node cannot wedge operation_in_progress?)" do
    audit = make_audit
    event = precreate_event(audit: audit)
    event.update_columns(status: "running", updated_at: 2.hours.ago)
    make_task(id: "zombie", audit_id: audit.id, status: "running", reconciled_status: "running")
    @node.update_columns(disconnected: true) # node dead → not online

    Agent::TaskReconciler.new.call
    assert event.reload.updated_at < 1.hour.ago # NOT touched → StaleEventWorker will reap it
  end

  # callback: true for the same reason as the failed-task test above.
  test "drives a cancelled task to cancel! (not fail!), and still delivers the callback" do
    audit = make_audit
    event = precreate_event(audit: audit, callback: true)
    make_task(audit_id: audit.id, status: "cancelled")
    Agent::TaskReconciler.new.call
    assert_equal "cancelled", event.reload.status
    assert_equal 1, CallbackWorker.jobs.size, "a cancellation must still fire its callback"
  end

  test "does not re-drive a terminal event when re-invoked (idempotent)" do
    audit = make_audit
    event = precreate_event(audit: audit)
    task = make_task(audit_id: audit.id, status: "completed")

    Agent::TaskReconciler.new.call
    completed_at = event.reload.updated_at
    # a stray re-emission at the same terminal status must not re-fire
    task.update_columns(reconciled_status: "running")
    Agent::TaskReconciler.new.call
    assert event.reload.success?
    assert_equal completed_at.to_i, event.updated_at.to_i
  end

  # The structural invariant, and the only assertion here that can detect the
  # in-transaction-enqueue bug: CallbackWorker re-reads the EventLog on a DIFFERENT
  # connection, which no single-connection test can simulate, so we assert the ordering
  # property instead — nothing may be pushed to Redis before COMMIT.
  #
  # The outer ActiveRecord::Base.transaction is REQUIRED and must not be simplified away
  # or changed to `requires_new: true`. The transactional-fixture transaction is
  # non-joinable, so this opens a joinable savepoint transaction (a SavepointTransaction,
  # not a RealTransaction — under transactional fixtures nothing here is the outermost
  # transaction); `with_lock` calls plain `transaction` with no requires_new:, which JOINS
  # it rather than opening a savepoint of its own, so the deferred block is registered on
  # THIS transaction and cannot fire until the block closes. Without the fix, perform_async
  # runs inline and the inner assertion fails.
  #
  # The boundary this observes is therefore `RELEASE SAVEPOINT`, not a literal `COMMIT` —
  # which is the most a single-connection test can prove, and it is the right assertion:
  # what matters is that the push is registered as an after-commit callback of the
  # outermost-visible transaction rather than firing inline.
  test "does not enqueue the callback until the transition commits" do
    audit = make_audit
    event = precreate_event(audit: audit, callback: true)
    make_task(audit_id: audit.id, status: "completed")

    ActiveRecord::Base.transaction do
      Agent::TaskReconciler.new.call
      assert event.reload.success?
      assert_equal 0, CallbackWorker.jobs.size, "callback must not be enqueued before commit"
    end

    assert_equal 1, CallbackWorker.jobs.size
  end

  # Same shape as above, rolled back: a transition that never commits must send no
  # callback at all (the task stays unreconciled and retries on the next pass).
  test "sends no callback when the transition rolls back" do
    audit = make_audit
    event = precreate_event(audit: audit, callback: true)
    make_task(audit_id: audit.id, status: "completed")

    ActiveRecord::Base.transaction do
      Agent::TaskReconciler.new.call
      assert_equal 0, CallbackWorker.jobs.size
      raise ActiveRecord::Rollback
    end

    assert_equal 0, CallbackWorker.jobs.size, "a rolled-back transition must not fire a callback"
    assert event.reload.pending?
  end
end

##
# Payload-shape regression guard. NOTE: this does NOT reproduce the pre-commit-read bug —
# CallbackWorker.drain runs on the same connection after the reconciler's transaction has
# closed, so it reads correct state with or without the deferred enqueue. It exists only to
# pin the shape of what a completed backup sends (success + the result summary).
class Agent::TaskReconcilerCallbackTest < ActiveSupport::TestCase
  # Scope WebMock to THIS test only — enabling it process-wide (via webmock/minitest)
  # would block the real HTTP that other suites make.
  include WebMock::API

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!
    CallbackWorker.clear
    @volume = volumes(:mysql)
    @node = nodes(:testone)
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def make_callback_event(audit)
    event = EventLog.new(locale: "volume.backup", locale_keys: {}, status: "pending", audit: audit,
      event_code: Agent::TaskReconcilerTest::BACKUP_CODE)
    event.labels = {"callback_url" => "https://cb.example/hook", "callback_auth" => "Bearer x"}
    event.volumes << @volume
    event.deployments << @volume.deployment if @volume.deployment
    event.save!
    event
  end

  test "a completed backup posts success: true with the result summary (payload shape only)" do
    audit = Audit.create!(event: "backup.create", rel_id: @volume.id, rel_model: "Volume")
    make_callback_event audit
    AgentTask.create!(id: "cb1", name: "volume.backup", status: "completed", audit_id: audit.id,
      volume: @volume.name, node_id: @node.id, project_id: @volume.deployment&.id.to_s,
      result: {"last_backup" => 1_700_000_000, "size" => 4096})

    stub_request(:post, "https://cb.example/hook").to_return(status: 200, body: "")

    Agent::TaskReconciler.new.call
    assert_equal 1, CallbackWorker.jobs.size
    # perform_one, NOT drain: drain loops `while jobs.any?`, and CallbackWorker's active-event
    # guard re-enqueues, so a future widening of that guard (e.g. `if event&.active?` ->
    # `if event`) would make drain spin forever and wedge CI instead of failing. perform_one
    # runs exactly one job, so a mis-guarded worker fails this test immediately.
    CallbackWorker.perform_one

    assert_requested(:post, "https://cb.example/hook") do |req|
      body = JSON.parse(req.body)
      assert_equal true, body["success"]
      assert body["data"].any? { |d| d.to_s.include?("Last backup:") }, "expected the result summary in data"
      true
    end
  end

  # The counterweight to the fix: suppressing spurious `success: false` must not suppress
  # genuine ones. A really-failed task still has to POST success: false end-to-end.
  test "a failed backup posts success: false" do
    audit = Audit.create!(event: "backup.create", rel_id: @volume.id, rel_model: "Volume")
    make_callback_event audit
    AgentTask.create!(id: "cb2", name: "volume.backup", status: "failed", audit_id: audit.id,
      volume: @volume.name, node_id: @node.id, project_id: @volume.deployment&.id.to_s,
      result: {"output" => "borg blew up"})

    stub_request(:post, "https://cb.example/hook").to_return(status: 200, body: "")

    Agent::TaskReconciler.new.call
    assert_equal 1, CallbackWorker.jobs.size
    CallbackWorker.perform_one

    assert_requested(:post, "https://cb.example/hook") do |req|
      assert_equal false, JSON.parse(req.body)["success"]
      true
    end
  end
end
