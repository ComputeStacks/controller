require "test_helper"

##
# Deleting the TEMPORARY archive a clone took of its source volume.
#
# The sweeper re-offers every row in `VolumeCloneJob.needs_snapshot_cleanup` every 15 seconds,
# so the ONLY things that stop this worker running forever are stamping `snapshot_trashed_at`
# or pushing `next_cleanup_at` into the future. Every test below therefore ends with
# #assert_no_hot_loop!, which is the property the whole class is built around: a plain `return`
# anywhere in here mints a fresh `backup.delete` agent task four times a minute, indefinitely.
class VolumeWorkers::TrashCloneSnapshotWorkerTest < ActiveSupport::TestCase
  include CloneTestHelpers

  ABANDONED_CODE = "0b93af5162c7de84".freeze

  setup do
    @source = volumes(:mysql)
    @target = volumes(:wordpress_web)
    @archive = archive_name("clone-7f3a")
  end

  def trash!(job, fake = FakeAgentClient.new)
    with_fake_agent(fake) do
      VolumeWorkers::TrashCloneSnapshotWorker.new.perform(job.id)
    end
    fake
  end

  def owned_job(**attrs)
    make_clone_job(
      volume: @target,
      source_volume: @source,
      state: VolumeCloneJob::STATE_COMPLETED,
      owns_snapshot: true,
      next_cleanup_at: 1.minute.ago,
      **attrs
    )
  end

  # The invariant: no exit path may leave the row still matching `needs_snapshot_cleanup` with
  # its `next_cleanup_at` unmoved — that is a 15s hot loop.
  def assert_no_hot_loop!(job, previous_cleanup_at)
    job.reload
    still_due = VolumeCloneJob.needs_snapshot_cleanup.exists?(id: job.id)
    return unless still_due
    assert_not_equal previous_cleanup_at&.to_i, job.next_cleanup_at&.to_i,
      "row is still due for cleanup with an unchanged next_cleanup_at: 15s hot loop"
    assert job.next_cleanup_at > Time.now, "a row still owing cleanup must be scheduled forward"
  end

  # --- deleting ---------------------------------------------------------------------

  test "deletes the archive it recorded and stamps the row" do
    job = owned_job(archive_name: @archive)
    before = job.reload.next_cleanup_at

    fake = trash!(job)

    deletes = fake.tasks_named("backup.delete")
    assert_equal 1, deletes.count
    assert_equal @archive, deletes.first[:archive]
    assert_equal @source.name, deletes.first[:volume], "the snapshot lives on the SOURCE volume"

    job.reload
    assert_not_nil job.snapshot_trashed_at
    assert_nil job.next_cleanup_at
    assert_equal 0, job.cleanup_attempts
    assert_no_hot_loop!(job, before)
  end

  test "resolves the archive from the clone label and persists what it found" do
    resolved = archive_name("lbl-3c9d")
    seed_archives(@source, [auto_archive_name(at: 2.days.ago), resolved])
    job = owned_job(archive_name: nil, clone_label: "lbl-3c9d")
    before = job.reload.next_cleanup_at

    fake = trash!(job)

    assert_equal resolved, fake.tasks_named("backup.delete").first[:archive]
    job.reload
    assert_equal resolved, job.archive_name, "a later attempt must not have to re-derive it"
    assert_not_nil job.snapshot_trashed_at
    assert_no_hot_loop!(job, before)
  end

  # --- nothing to delete ------------------------------------------------------------

  test "stamps and stops when the source volume is gone" do
    job = owned_job(archive_name: @archive)
    job.update_columns(source_volume_id: 999_999_999)
    before = job.reload.next_cleanup_at

    fake = trash!(job)

    assert_empty fake.calls_of(:create_task)
    job.reload
    assert_not_nil job.snapshot_trashed_at
    assert_nil job.next_cleanup_at
    assert_equal 0, job.cleanup_attempts, "a permanent answer must not burn the retry budget"
    assert_no_hot_loop!(job, before)
  end

  test "stamps and stops when the label matches no archive on the repo" do
    seed_archives(@source, [auto_archive_name(at: 2.days.ago)])
    job = owned_job(archive_name: nil, clone_label: "never-landed")
    before = job.reload.next_cleanup_at

    fake = trash!(job)

    assert_empty fake.calls_of(:create_task), "proof the backup never landed, not a transient failure"
    job.reload
    assert_not_nil job.snapshot_trashed_at
    assert_nil job.next_cleanup_at
    assert_equal 0, job.cleanup_attempts
    assert_no_hot_loop!(job, before)
  end

  test "stamps and stops when there is neither an archive name nor a label" do
    job = owned_job(archive_name: nil, clone_label: nil)
    before = job.reload.next_cleanup_at

    trash!(job)

    job.reload
    assert_not_nil job.snapshot_trashed_at
    assert_no_hot_loop!(job, before)
  end

  # --- backing off ------------------------------------------------------------------

  test "a refused dispatch backs off and pushes next_cleanup_at forward" do
    job = owned_job(archive_name: @archive)
    before = job.reload.next_cleanup_at

    trash!(job, FakeAgentClient.new(create_task: false))

    job.reload
    assert_equal 1, job.cleanup_attempts
    assert_nil job.snapshot_trashed_at
    assert job.next_cleanup_at > before, "next_cleanup_at must grow"
    assert job.next_cleanup_at > Time.now
    assert_in_delta 1.hour.from_now.to_i, job.next_cleanup_at.to_i, 120
    assert_no_hot_loop!(job, before)
  end

  test "an exception during the delete backs off rather than dying" do
    job = owned_job(archive_name: @archive)
    before = job.reload.next_cleanup_at

    exploding = FakeAgentClient.new(put_volume: ->(*) { raise "node exploded" })
    assert_nothing_raised { trash!(job, exploding) }

    job.reload
    assert_equal 1, job.cleanup_attempts
    assert_nil job.snapshot_trashed_at
    assert job.next_cleanup_at > before
    assert_no_hot_loop!(job, before)
  end

  test "the backoff grows and stays capped" do
    job = owned_job(archive_name: @archive)

    [1.hour, 2.hours, 4.hours, 8.hours, 12.hours].each_with_index do |expected, i|
      job.update!(cleanup_attempts: i, next_cleanup_at: 1.minute.ago, snapshot_trashed_at: nil)
      trash!(job, FakeAgentClient.new(create_task: false))
      job.reload
      assert_equal i + 1, job.cleanup_attempts
      assert_in_delta expected.from_now.to_i, job.next_cleanup_at.to_i, 120,
        "attempt #{i + 1} should back off #{expected.inspect}"
    end
  end

  test "gives up at MAX_CLEANUP_ATTEMPTS, stamps anyway and records the abandoned snapshot" do
    job = owned_job(archive_name: @archive,
      cleanup_attempts: VolumeCloneJob::MAX_CLEANUP_ATTEMPTS - 1)
    before = job.reload.next_cleanup_at

    assert_difference "SystemEvent.where(event_code: '#{ABANDONED_CODE}').count", 1 do
      trash!(job, FakeAgentClient.new(create_task: false))
    end

    job.reload
    assert_equal VolumeCloneJob::MAX_CLEANUP_ATTEMPTS, job.cleanup_attempts
    assert_not_nil job.snapshot_trashed_at, "stamped even though the archive is still on disk"
    assert_nil job.next_cleanup_at
    assert_no_hot_loop!(job, before)

    system_event = SystemEvent.where(event_code: ABANDONED_CODE).last
    assert_includes system_event.message, @archive
    assert_includes system_event.message, @source.name
    assert_equal "warn", system_event.log_level
    assert_equal job.id, system_event.data["clone_job_id"]
    assert_equal @archive, system_event.data["archive"]
  end

  # --- guards -----------------------------------------------------------------------

  test "does nothing for a row that does not own its snapshot" do
    job = owned_job(archive_name: @archive, owns_snapshot: false)

    fake = trash!(job)

    assert_empty fake.calls_of(:create_task), "a user's real backup is never ours to delete"
    assert_nil job.reload.snapshot_trashed_at
    assert_not VolumeCloneJob.needs_snapshot_cleanup.exists?(id: job.id)
  end

  test "does nothing for a row whose snapshot was already trashed" do
    job = owned_job(archive_name: @archive, snapshot_trashed_at: 1.hour.ago)
    stamped_at = job.reload.snapshot_trashed_at

    fake = trash!(job)

    assert_empty fake.calls_of(:create_task)
    assert_equal stamped_at.to_i, job.reload.snapshot_trashed_at.to_i
  end

  test "a deleted row is a no-op" do
    job = owned_job(archive_name: @archive)
    id = job.id
    job.destroy!

    assert_nothing_raised do
      with_fake_agent { VolumeWorkers::TrashCloneSnapshotWorker.new.perform(id) }
    end
  end

  # --- the whole exit surface at once ------------------------------------------------

  test "no exit path leaves the row hot-looping" do
    paths = {
      "archive deleted" => [{archive_name: @archive}, FakeAgentClient.new, nil],
      "resolved from label" => [
        {archive_name: nil, clone_label: "hot-loop-lbl"},
        FakeAgentClient.new,
        -> { seed_archives(@source, [archive_name("hot-loop-lbl")]) }
      ],
      "label matches nothing" => [
        {archive_name: nil, clone_label: "hot-loop-missing"},
        FakeAgentClient.new,
        -> { seed_archives(@source, []) }
      ],
      "no archive and no label" => [{archive_name: nil, clone_label: nil}, FakeAgentClient.new, nil],
      "dispatch refused" => [{archive_name: @archive}, FakeAgentClient.new(create_task: false), nil],
      "delete raises" => [
        {archive_name: @archive},
        FakeAgentClient.new(put_volume: ->(*) { raise "node exploded" }),
        nil
      ],
      "gave up" => [
        {archive_name: @archive, cleanup_attempts: VolumeCloneJob::MAX_CLEANUP_ATTEMPTS - 1},
        FakeAgentClient.new(create_task: false),
        nil
      ]
    }

    paths.each do |name, (attrs, fake, setup)|
      VolumeCloneJob.delete_all
      setup&.call
      job = owned_job(**attrs)
      before = job.reload.next_cleanup_at

      trash!(job, fake)

      job.reload
      still_due = VolumeCloneJob.needs_snapshot_cleanup.exists?(id: job.id)
      assert_not(still_due && job.next_cleanup_at.to_i == before.to_i,
        "#{name}: row is still due with an unchanged next_cleanup_at (15s hot loop)")
    end
  end

  # Adoption exists so one backup serves N clones, and SOURCE_CLAIM_STATES deliberately
  # excludes the restore states so adopters run in parallel with the owner. The owner's +2h
  # cleanup therefore comes due while an adopter can still be gated behind the per-node borg
  # cap, or partway through a 24h restore. Deleting the archive there breaks their restore.
  test "waits while an adopter is still restoring from the same archive" do
    archive = archive_name("shared")
    seed_archives @source, [archive]

    owner = make_clone_job(volume: @target, source_volume: @source,
      state: VolumeCloneJob::STATE_COMPLETED, archive_name: archive, clone_label: "shared",
      owns_snapshot: true, finished_at: 2.hours.ago, next_cleanup_at: 1.minute.ago)
    adopter = make_clone_job(volume: volumes(:nginx_web), source_volume: @source,
      state: VolumeCloneJob::STATE_AWAITING_RESTORE, archive_name: archive,
      owns_snapshot: false)

    fake = FakeAgentClient.new
    with_fake_agent(fake) { VolumeWorkers::TrashCloneSnapshotWorker.new.perform(owner.id) }

    owner.reload
    assert_nil owner.snapshot_trashed_at, "must not close the row out while an adopter needs it"
    refute fake.called?(:create_task), "must not dispatch a delete under a live adopter"
    assert_operator owner.next_cleanup_at, :>, Time.now
    # Waiting must not burn the retry budget — the adopter is bounded, the budget is not.
    assert_equal 0, owner.cleanup_attempts

    # Once the adopter finishes, the archive is reaped normally.
    adopter.update!(state: VolumeCloneJob::STATE_COMPLETED, finished_at: Time.now)
    with_fake_agent(fake) { VolumeWorkers::TrashCloneSnapshotWorker.new.perform(owner.id) }
    assert_not_nil owner.reload.snapshot_trashed_at
  end
end
