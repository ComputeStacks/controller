require "test_helper"

##
# The same-source claim must be a total order, not a mutual veto.
#
# Two volumes cloning from one source is the headline case this feature exists for (a
# WordPress project clones its web volume and its MySQL volume, and a service can mount two
# volumes off the same source). Both jobs are enqueued together, both reach
# `dispatching_backup` — which is itself one of SOURCE_CLAIM_STATES — and if the claim check
# is symmetric each sees the other as the holder and neither can ever dispatch.
class VolumeServices::CloneDeadlockTest < ActiveSupport::TestCase
  include CloneTestHelpers

  SVC = VolumeServices::CloneStepService

  def stub_service(job)
    svc = SVC.new(job)
    svc.define_singleton_method(:container_built?) { |_volume| true }
    svc.define_singleton_method(:project_node!) { |_node| true }
    svc
  end

  def tick!(job, fake)
    with_fake_agent(fake) { stub_service(job).perform }
    job.reload
  end

  test "two same-source jobs in dispatching_backup do not gate each other forever" do
    first = make_clone_job(
      volume: volumes(:wordpress_web),
      source_volume: volumes(:mysql),
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "aaaa1111"
    )
    second = make_clone_job(
      volume: volumes(:nginx_web),
      source_volume: volumes(:mysql),
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "bbbb2222"
    )

    fake = FakeAgentClient.new
    3.times do
      tick! first, fake
      tick! second, fake
    end

    # Exactly one of them must have taken the backup. Both gated is the deadlock; both
    # dispatched is the double-borg-run this gate exists to prevent.
    dispatched = [first, second].count { |j| j.backup_task_id.present? }
    assert_equal 1, dispatched,
      "expected exactly one dispatch, got #{dispatched} " \
      "(first=#{first.state}/#{first.gate_reason.inspect}, " \
      "second=#{second.state}/#{second.gate_reason.inspect})"
  end

  test "the claim holder is the lowest id, so the loser waits rather than both stalling" do
    # clone_label is normally set in resolving_source; these rows start mid-machine.
    first = make_clone_job(
      volume: volumes(:wordpress_web),
      source_volume: volumes(:mysql),
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "aaaa1111"
    )
    second = make_clone_job(
      volume: volumes(:nginx_web),
      source_volume: volumes(:mysql),
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "bbbb2222"
    )
    assert first.id < second.id, "fixture ordering assumption"

    fake = FakeAgentClient.new
    tick! second, fake
    assert second.gated?, "the higher id must yield"

    tick! first, fake
    refute first.gated?, "the lowest id must never be blocked by a peer — that is the deadlock"
    assert first.backup_task_id.present?
  end

  # A source-less row (its source volume was destroyed mid-clone) must not be treated as a
  # sibling of every other source-less row.
  test "a nil source volume does not create a phantom claim" do
    orphan = make_clone_job(
      volume: volumes(:wordpress_web),
      source_volume: nil,
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP
    )
    make_clone_job(
      volume: volumes(:nginx_web),
      source_volume: nil,
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP
    )

    svc = stub_service(orphan)
    refute svc.send(:sibling_claim?), "a nil source must not match other nil-source rows"
  end

  # --- crash recovery ------------------------------------------------------------------

  # The task id is persisted inside the tick's transaction, so it is uncommitted while the
  # POST is in flight. A rollback (or SIGKILL) after a successful POST must not lose it, or
  # re-entry mints a fresh id and POSTs a SECOND full borg run whose archive nothing reaps.
  test "a task id survives losing the transaction, so a landed POST is never re-POSTed" do
    job = make_clone_job(
      volume: volumes(:wordpress_web),
      source_volume: volumes(:mysql),
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "cccc3333"
    )

    fake = FakeAgentClient.new
    tick! job, fake
    first_id = job.backup_task_id
    assert first_id.present?

    # Simulate the rollback: the agent kept the task, the row lost every trace of it.
    make_agent_task(id: first_id, name: "volume.backup", status: "running", volume: volumes(:mysql))
    job.update!(backup_task_id: nil, backup_dispatched_at: nil,
      state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, entered_state_at: 5.minutes.ago)

    posts_before = fake.calls_of(:create_task).count
    tick! job, fake

    assert_equal first_id, job.backup_task_id, "the id must be re-derivable, not re-minted"
    assert_equal posts_before, fake.calls_of(:create_task).count, "a landed POST must never be re-sent"
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
  end
end
