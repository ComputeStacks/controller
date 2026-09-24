module VolumeServices
  ##
  # Advance ONE VolumeCloneJob through its state machine, exactly one tick at a time.
  #
  # This is the replacement for the old VolumeServices::CloneVolumeService, which held the
  # whole clone in one `Timeout` + `sleep` loop inside ProcessOrderWorker (annihilated by
  # supervisord's `stopsignal=KILL` on every deploy). Here the `volume_clone_jobs` row is the
  # only durable state: every tick is short, idempotent and crash-safe, and the clock sweeper
  # (VolumeWorkers::CloneSweepWorker, 15s) is the only thing that ever enqueues us.
  #
  # Execution contract (all of it is load-bearing):
  #
  # * **One row lock, no Sidekiq lock.** Everything runs inside `job.with_lock`, exactly like
  #   Agent::TaskReconciler#react — state is re-read under the lock, so two overlapping ticks
  #   serialize instead of double-dispatching. A `sidekiq-unique-jobs` lock was rejected
  #   deliberately (see the frozen contract): a SIGKILLed `UntilExecuted` job orphans its lock
  #   for 600s, and `OnConflict::Reject` pushes to the dead set.
  # * **Up to MAX_ADVANCES states per invocation**, stopping at the first state that must wait.
  #   Advancing sets `next_poll_at` to now, so a job that runs out of advances is picked up by
  #   the very next sweep rather than sitting idle.
  # * **At most ONE outbound agent operation per invocation** — either one forced
  #   Agent::ChangelogProjector pass OR one dispatch (`create_backup!`/`restore_backup!`, which
  #   is itself `put_volume` + `create_task`). A tick that has spent its budget and then
  #   advances into a state that needs another stops and lets the next sweep tick do it. We
  #   never sleep and never loop-poll. (`Deployment::Container#built?` is a Docker read on a
  #   different channel and is not part of this budget.)
  # * **The umbrella event is touched every tick**, gated ticks included, which is what keeps
  #   EventWorkers::StaleEventWorker (fails `running` events after 1h) and
  #   EventLog.clean_event_status! (cancels anything untouched for 2h) off a legitimately long
  #   clone.
  # * **`next_poll_at` is advanced here, inside the lock** — never by the sweeper.
  # * **An unexpected exception is never swallowed into a terminal state.** It bumps
  #   `consecutive_errors` and backs off; VolumeCloneJob.overdue (>= MAX_CONSECUTIVE_ERRORS)
  #   is what forces a deterministically-raising job terminal, so it still reaches the terminal
  #   funnel and still schedules its snapshot cleanup.
  #
  # `#enter_terminal!` is the ONE way any state (or the sweeper) reaches a terminal state.
  # It is public for that reason.
  #
  # @!attribute job
  #   @return [VolumeCloneJob]
  # @!attribute errors
  #   @return [Array<String>]
  class CloneStepService
    # Concurrent borg backup/restore tasks allowed per node before a dispatch is gated.
    MAX_CONCURRENT_BORG_PER_NODE = (ENV["CLONE_MAX_BORG_PER_NODE"].presence || 4).to_i

    # States one invocation may advance through before yielding back to the sweeper.
    MAX_ADVANCES = 4

    # Settle window between entering a dispatch state and the POST going out. A task the
    # agent already accepted only becomes visible locally on the next changelog pass (15s),
    # so we always give the projection a chance to reveal an earlier, crashed-out POST
    # before sending one — re-POSTing a backup is expensive and user-visible.
    DISPATCH_GRACE = 60.seconds

    # Absolute cap on time spent waiting for a gate to open. Gated time does not consume the
    # state deadline (see #gated!), so without this a permanently-closed gate — a stale `active`
    # AgentTask row on a live node, a wedged sibling holding the same-source claim — would park
    # a clone forever with no failure and no alert.
    #
    # Defined on the model: VolumeCloneJob.overdue has to grant the same exemption this class's
    # #enforce_deadline! does, or the sweeper force-fails jobs that are correctly waiting.
    MAX_GATED_TIME = VolumeCloneJob::MAX_GATED_TIME

    # How long an awaiting_* state tolerates its AgentTask row never showing up at all.
    TASK_APPEARANCE_GRACE = 30.minutes

    # A snapshot younger than this is reused instead of taking a fresh one.
    RECENT_ARCHIVE_WINDOW = 10.minutes

    # Minimum spacing between on-demand changelog projections for one job.
    PROJECT_INTERVAL = 5.seconds

    # Sibling states whose `archive_name` we may adopt: at or after discovery, and still
    # working. Terminal siblings are excluded on purpose — a completed sibling's snapshot is
    # already queued for trashing (next_cleanup_at), and a failed one's archive may be partial.
    ADOPTABLE_STATES = [
      VolumeCloneJob::STATE_DISCOVERING_ARCHIVE,
      VolumeCloneJob::STATE_DISPATCHING_RESTORE,
      VolumeCloneJob::STATE_AWAITING_RESTORE
    ].freeze

    UMBRELLA_EVENT_CODE = "5c1e7a3f9b024d68"
    ARCHIVE_MISSING_EVENT_CODE = "d41b0aa5c73f9e82"
    DEADLINE_EVENT_CODE = "a80f5d1c46e3b927"
    GATE_EVENT_CODE = "c17e34b8d5a09f26"
    ABANDONED_SNAPSHOT_EVENT_CODE = "0b93af5162c7de84"
    EXCEPTION_EVENT_CODE = "b4e181611d7c5423"
    CONTAINER_EVENT_CODE = "53a075e943b51b72"
    SOURCE_EVENT_CODE = "9a69eb920764c1da"
    BACKUP_FAILED_EVENT_CODE = "7704f466b97ac18c"
    RESTORE_FAILED_EVENT_CODE = "9858861ab2912307"
    BACKUP_PROGRESS_EVENT_CODE = "67e93090ab029cf5"
    RESTORE_PROGRESS_EVENT_CODE = "79e6e2d3860d1806"
    ORDER_EVENT_CODE = "3f7c2b90a15de846"

    # Per-state event code for "this state ran out of time", so the failure reads as the thing
    # that actually failed rather than a generic timeout.
    DEADLINE_EVENT_CODES = {
      VolumeCloneJob::STATE_AWAITING_CONTAINER => CONTAINER_EVENT_CODE,
      VolumeCloneJob::STATE_RESOLVING_SOURCE => SOURCE_EVENT_CODE,
      VolumeCloneJob::STATE_DISPATCHING_BACKUP => BACKUP_FAILED_EVENT_CODE,
      VolumeCloneJob::STATE_AWAITING_BACKUP => BACKUP_FAILED_EVENT_CODE,
      VolumeCloneJob::STATE_DISCOVERING_ARCHIVE => ARCHIVE_MISSING_EVENT_CODE,
      VolumeCloneJob::STATE_DISPATCHING_RESTORE => RESTORE_FAILED_EVENT_CODE,
      VolumeCloneJob::STATE_AWAITING_RESTORE => RESTORE_FAILED_EVENT_CODE
    }.freeze

    attr_accessor :job,
      :errors,
      :http_spent,
      :advances

    # @param [VolumeCloneJob] job
    def initialize(job)
      self.job = job
      self.errors = []
      self.http_spent = false
      self.advances = 0
    end

    # Run one tick.
    #
    # @return [Boolean] true when the tick completed (including when it legitimately parked,
    #   gated, or drove the job terminal); false only when it raised — in which case the row
    #   already carries the incremented `consecutive_errors` and a backed-off `next_poll_at`.
    def perform
      return false if job.nil?
      job.with_lock { tick }
      true
    rescue => e
      record_exception(e)
      false
    end

    # The single terminal funnel: every terminal transition in the machine (and the sweeper's
    # force-termination of an overdue / repeatedly-raising job) goes through here.
    #
    # In one transaction it writes the terminal state, `finished_at`, `last_error` and the
    # snapshot cleanup schedule, then drives the umbrella event and records the outcome — on
    # the event itself and, once, on the order's provision event (each clone carries its OWN
    # audit, so clone events never render on the order page; this line is what keeps order
    # forensics intact).
    #
    # Tolerates an umbrella event that a reaper already terminated: `done!`/`fail!`/`cancel!`
    # return false there, and the SystemEvent for a failure is emitted regardless.
    #
    # Idempotent — a job that is already terminal is left exactly as it is.
    #
    # @param [String] new_state one of VolumeCloneJob::TERMINAL_STATES
    # @param [String, nil] reason
    # @param [String, nil] event_code
    # @return [Boolean]
    def enter_terminal!(new_state, reason: nil, event_code: nil)
      job.reload if job.changed?
      job.with_lock do
        next if job.terminal?

        errors << reason if reason.present? && new_state != VolumeCloneJob::STATE_COMPLETED

        attrs = {
          state: new_state,
          finished_at: Time.now,
          last_error: reason.presence
          # NB `next_poll_at` is NOT NULL in the schema and therefore cannot be cleared here.
          # It does not need to be: every due/overdue query is scoped to `working`, so a stale
          # due-time on a terminal row is inert.
        }
        # The temporary snapshot is the only forensic artifact of a failed clone, so a failure
        # keeps it around far longer than a success does.
        if job.owns_snapshot && job.snapshot_trashed_at.nil?
          attrs[:next_cleanup_at] = (new_state == VolumeCloneJob::STATE_COMPLETED) ? 2.hours.from_now : 24.hours.from_now
        end
        job.update!(attrs)

        drive_umbrella_event(new_state, reason, event_code)
        warn_abandoned_snapshot!(new_state)
        record_order_summary(new_state, reason)
      end
      true
    end

    private

    # One pass: keep the event alive, honour cancellation, then advance while we can.
    def tick
      # Before anything else, and on gated ticks too: StaleEventWorker (1h) and
      # EventLog.clean_event_status! (2h) both key off `updated_at`.
      job.event_log&.touch

      return true if job.terminal?

      reason = cancellation_reason
      if reason
        enter_terminal!(VolumeCloneJob::STATE_CANCELLED, reason: reason, event_code: UMBRELLA_EVENT_CODE)
        return true
      end

      heal_state_stamps!

      MAX_ADVANCES.times do
        break unless job.working?
        break if enforce_deadline!
        break unless step == :advanced
        self.advances += 1
      end

      # A clean tick clears the error streak. `consecutive_errors` means "N ticks in a row
      # raised", and only enter_state! zeroed it — so a job that legitimately holds in one
      # state for hours (awaiting_restore has a 24h budget) accumulated *lifetime* errors, and
      # five transient blips spread across a day would trip the sweeper's force-terminate as
      # if the tick were deterministically broken.
      job.update!(consecutive_errors: 0) if job.working? && job.consecutive_errors > 0
      true
    end

    # A working row must always carry `entered_state_at` and (where the state has a budget)
    # `state_deadline_at`: the dispatch settle window and the awaiting_* grace are measured
    # from the former, and VolumeCloneJob.overdue can only see rows that have the latter.
    # enter_state! sets both; this repairs a row that reached a working state any other way,
    # so it can never sit in a state with nothing bounding it.
    def heal_state_stamps!
      return unless job.working?
      attrs = {}
      attrs[:entered_state_at] = Time.now if job.entered_state_at.nil?
      budget = VolumeCloneJob::STATE_DEADLINES[job.state]
      if job.state_deadline_at.nil? && budget
        attrs[:state_deadline_at] = (attrs[:entered_state_at] || job.entered_state_at) + budget
      end
      job.update!(attrs) if attrs.any?
    end

    # @return [String, nil] why this clone is moot, or nil to carry on.
    def cancellation_reason
      return "Target volume no longer exists." if job.volume.nil?
      return "Source volume no longer exists." if job.source_volume.nil?
      return "Project has been trashed." if job.deployment&.trashed?
      nil
    end

    # @return [Boolean] true when the state's budget was exhausted and the job was terminated.
    def enforce_deadline!
      deadline = job.state_deadline_at
      return false if deadline.nil? || deadline > Time.now

      # A gated job's deadline is only pushed forward by #gated!, i.e. on a tick. If ticks stop
      # for longer than the state budget — sweeper outage, Sidekiq backlog, a long deploy — the
      # first tick back would fail a job that was doing nothing wrong. Gated time is bounded by
      # MAX_GATED_TIME instead, which #gated! enforces on its own.
      return false if job.gated? && job.gate_blocked_since > MAX_GATED_TIME.ago

      code = DEADLINE_EVENT_CODES.fetch(job.state, DEADLINE_EVENT_CODE)
      reason = "Timed out in state '#{job.state}' (entered #{job.entered_state_at&.iso8601})."

      # A wedged changelog cursor looks exactly like "the archive hasn't been created yet" and
      # never self-resolves, so this one needs an operator, not just a user-facing event.
      if job.state == VolumeCloneJob::STATE_DISCOVERING_ARCHIVE
        SystemEvent.create!(
          message: "Volume clone never found its snapshot (clone job #{job.id})",
          log_level: "warn",
          data: {
            clone_job: job.id,
            volume_id: job.volume_id,
            source_volume_id: job.source_volume_id,
            node_id: job.node_id,
            clone_label: job.clone_label,
            backup_task_id: job.backup_task_id
          },
          event_code: ARCHIVE_MISSING_EVENT_CODE
        )
      end

      enter_terminal!(VolumeCloneJob::STATE_FAILED, reason: reason, event_code: code)
      true
    end

    # @return [Symbol] :advanced when the job changed state, :wait otherwise.
    def step
      case job.state
      when VolumeCloneJob::STATE_PENDING then step_pending
      when VolumeCloneJob::STATE_AWAITING_CONTAINER then step_awaiting_container
      when VolumeCloneJob::STATE_RESOLVING_SOURCE then step_resolving_source
      when VolumeCloneJob::STATE_DISPATCHING_BACKUP then step_dispatch(:backup)
      when VolumeCloneJob::STATE_AWAITING_BACKUP then step_awaiting(:backup)
      when VolumeCloneJob::STATE_DISCOVERING_ARCHIVE then step_discovering_archive
      when VolumeCloneJob::STATE_DISPATCHING_RESTORE then step_dispatch(:restore)
      when VolumeCloneJob::STATE_AWAITING_RESTORE then step_awaiting(:restore)
      else :wait
      end
    end

    ##
    # pending -> awaiting_container
    #
    # Creates (once) the umbrella `volumes.clone` event and starts it in the same transaction
    # as the state advance. It is never left `pending`: clean_event_status! reaps pending
    # events too.
    def step_pending
      ensure_umbrella_event!
      job.enter_state!(VolumeCloneJob::STATE_AWAITING_CONTAINER)
      :advanced
    end

    ##
    # awaiting_container -> resolving_source
    #
    # The restore lands inside the owning container's mount, so it has to exist first.
    def step_awaiting_container
      return hold! unless container_built?(job.volume)
      job.enter_state!(VolumeCloneJob::STATE_RESOLVING_SOURCE)
      :advanced
    end

    ##
    # resolving_source -> dispatching_backup | dispatching_restore
    #
    # Pins the node (the borg repo is node-bound) and picks between the three fast paths and a
    # fresh backup. `owns_snapshot` stays false on every fast path so we never trash a real
    # user backup.
    def step_resolving_source
      source = job.source_volume
      target = job.volume
      return fail_state!("Source volume is no longer available.", SOURCE_EVENT_CODE) if source.nil? || target.nil?
      unless target.region_id == source.region_id
        return fail_state!("Requested source volume is not in this region.", SOURCE_EVENT_CODE)
      end

      node = source.active_node
      # TRANSIENT: no online node currently holds the source. Wait it out (bounded by the
      # state deadline) rather than failing a clone over a node reboot.
      return hold! if node.nil?
      job.update!(node_id: node.id) unless job.node_id == node.id

      return adopt_archive!(job.requested_archive, "caller-supplied") if job.requested_archive.present?

      sibling = adoptable_archive
      return adopt_archive!(sibling, "in-flight clone of the same source") if sibling.present?

      recent = recent_archive_name(source)
      return adopt_archive!(recent, "recent snapshot") if recent.present?

      job.update!(clone_label: job.clone_label.presence || SecureRandom.hex(8))
      detail(BACKUP_PROGRESS_EVENT_CODE, "Creating snapshot of source volume #{source.csrn}")
      job.enter_state!(VolumeCloneJob::STATE_DISPATCHING_BACKUP)
      :advanced
    end

    ##
    # dispatching_backup / dispatching_restore
    #
    # Gate first, then the three-case dispatch re-entry:
    #   1. already stamped  -> advance, no POST;
    #   2. task row exists  -> the POST landed and we crashed before stamping: stamp, advance,
    #                          NEVER re-POST;
    #   3. neither, and past the settle window -> persist the id, create the child event, POST.
    def step_dispatch(kind)
      # Re-check adoption before gating. A follower that reached dispatching_backup and then got
      # parked behind a sibling's same-source claim would otherwise, once the claim released,
      # take its OWN backup of the same source under its own label — two full borg runs of one
      # 10GB volume, merely serialized rather than concurrent. Adoption is only decided in
      # resolving_source, which the follower is already past, so it has to be re-offered here.
      #
      # Only while nothing of ours is in flight: once backup_task_id is persisted the agent may
      # already hold the task, and abandoning it would orphan the archive it creates.
      if kind == :backup && job.backup_task_id.blank?
        adopted = adoptable_archive
        return adopt_archive!(adopted, "in-flight clone of the same source") if adopted.present?
      end

      gate = closed_gate
      return gated!(gate) if gate
      job.release_gate! if job.gated?

      return advance_to_awaiting(kind) if dispatched_at(kind).present?

      persisted = task_id(kind).presence

      # Look for the task under the DERIVED id even when nothing is persisted. `dispatch!` runs
      # inside this tick's transaction, so a POST can land and the id it wrote can still be
      # rolled away — checking only the persisted id would miss exactly the case this recovery
      # exists for and re-POST a second borg run. See #derived_task_id.
      jid = persisted || derived_task_id(kind)
      if AgentTask.exists?(id: jid)
        job.update!(task_id_column(kind) => jid, dispatched_column(kind) => Time.now)
        return advance_to_awaiting(kind)
      end

      # The settle window only buys something once a POST has actually been attempted: it gives
      # one that landed just before a crash a chance to show up in the projection, so we adopt
      # it instead of re-POSTing. With nothing persisted and no task row, waiting is pure dead
      # latency (60s here plus 60s again before the restore, per volume).
      return hold! if persisted.present? && (job.entered_state_at.nil? || job.entered_state_at > DISPATCH_GRACE.ago)
      # Budget spent elsewhere in this tick; the next sweep tick sends it.
      return defer! if http_spent

      dispatch!(kind)
    end

    ##
    # awaiting_backup / awaiting_restore
    #
    # The AgentTask row is node-reported truth (projected changelog); the EventLog is driven
    # independently by Agent::TaskReconciler and is deliberately NOT what we read here.
    def step_awaiting(kind)
      jid = task_id(kind)
      task = jid.present? ? AgentTask.find_by(id: jid) : nil

      if task.nil?
        if job.entered_state_at && job.entered_state_at < TASK_APPEARANCE_GRACE.ago
          return fail_state!("The #{task_name(kind)} task never appeared in the node's changelog.", failure_code(kind))
        end
        return hold!
      end

      case task.status
      when "completed"
        if kind == :backup
          detail(BACKUP_PROGRESS_EVENT_CODE, "Snapshot #{job.clone_label} created on #{job.source_volume&.csrn}.")
          job.enter_state!(VolumeCloneJob::STATE_DISCOVERING_ARCHIVE)
          :advanced
        else
          detail(RESTORE_PROGRESS_EVENT_CODE, "Restored #{job.archive_name} into #{job.volume&.csrn}.")
          enter_terminal!(VolumeCloneJob::STATE_COMPLETED, event_code: UMBRELLA_EVENT_CODE)
          :wait
        end
      when "failed", "cancelled"
        fail_state!(task_failure_reason(task), failure_code(kind))
      else
        # Still running. A 10GB volume can legitimately sit here for hours, and the agent only
        # emits a changelog row on a status TRANSITION, so the task row itself goes stale
        # mid-copy — there is no progress signal to read. What bounds this state is therefore
        # the flat 12h (backup) / 24h (restore) budget, not node liveness; see
        # #reassert_state_budget! for why the intended stall extension is not implemented.
        reassert_state_budget!
        hold!
      end
    end

    ##
    # discovering_archive -> dispatching_restore
    #
    # The agent picks the archive's timestamp suffix, so the only way to learn the raw name is
    # to read the projected repository back. `reset_repo_info!` is mandatory between forcing a
    # projection and re-reading: the memo on this object is exactly the bug that made the old
    # clone poll a frozen archive list for 300s.
    def step_discovering_archive
      node = job.node
      if node&.online? && !http_spent && (job.polled_at.nil? || job.polled_at < PROJECT_INTERVAL.ago)
        self.http_spent = true
        project_node!(node)
        job.update!(polled_at: Time.now)
      end

      source = job.source_volume
      name = nil
      if source && job.clone_label.present?
        source.reset_repo_info!
        name = source.find_archive_by_label(job.clone_label)
      end
      return hold! if name.blank?

      # We created it, so we are the ones who must trash it.
      job.update!(archive_name: name, owns_snapshot: true)
      detail(RESTORE_PROGRESS_EVENT_CODE, "Restoring snapshot #{name} from #{source.csrn}")
      job.enter_state!(VolumeCloneJob::STATE_DISPATCHING_RESTORE)
      :advanced
    end

    # --- state helpers -------------------------------------------------------------------

    def adopt_archive!(name, why)
      job.update!(archive_name: name, owns_snapshot: false)
      detail(RESTORE_PROGRESS_EVENT_CODE, "Restoring snapshot #{name} from source volume (#{why}).")
      job.enter_state!(VolumeCloneJob::STATE_DISPATCHING_RESTORE)
      :advanced
    end

    def advance_to_awaiting(kind)
      job.enter_state!((kind == :backup) ? VolumeCloneJob::STATE_AWAITING_BACKUP : VolumeCloneJob::STATE_AWAITING_RESTORE)
      :advanced
    end

    # The task id is DERIVED, not random, and that is load-bearing for crash recovery.
    #
    # `dispatch!` runs inside `perform`'s `job.with_lock` transaction, so the id it persists
    # before POSTing is uncommitted while the POST is in flight. If anything later in the same
    # tick raises — `enter_state!`, an event_details insert, the next state's work, since the
    # tick advances up to MAX_ADVANCES states after the POST — or the process is SIGKILLed
    # (production supervisord), the transaction rolls back and a random id would be lost while
    # the agent kept the task. Re-entry would then find no id, fail the `AgentTask.exists?`
    # check that is supposed to catch exactly this, mint a *new* id, and POST a second full
    # borg run of the same volume — whose archive nothing would ever clean up, since only the
    # recorded `archive_name` is reaped.
    #
    # Deriving from (job id, kind) makes re-entry regenerate the same id, so the recovery check
    # matches and we adopt the task instead of duplicating it. It also makes an ordinary
    # retry-after-rejected-dispatch idempotent by construction rather than by bookkeeping.
    #
    # @return [String] a stable UUID
    def derived_task_id(kind)
      Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "volume_clone_job/#{job.id}/#{kind}")
    end

    # Persist the id BEFORE the POST, create the child event in the same tick as the POST with
    # its `task_id` label already set, then dispatch.
    #
    # We deliberately do NOT set `current_audit` on either volume: correlation is by the
    # EventLog label, and the audit_id echoed to the agent is not trustworthy.
    def dispatch!(kind)
      jid = task_id(kind).presence || derived_task_id(kind)
      job.update!(task_id_column(kind) => jid) if task_id(kind) != jid
      ensure_child_event!(kind, jid)

      self.http_spent = true
      accepted = if kind == :backup
        job.source_volume.create_backup!(job.clone_label, task_id: jid)
      else
        job.volume.restore_backup!(job.archive_name, job.source_volume&.name, task_id: jid)
      end

      if accepted
        job.update!(dispatched_column(kind) => Time.now)
        return advance_to_awaiting(kind)
      end

      # Not a fixed try cap: the state deadline is what bounds this. Retrying re-uses the same
      # (persisted) task id, so a POST that actually landed can never become a second task.
      job.update!(dispatch_attempts: job.dispatch_attempts + 1)
      detail(failure_code(kind), "Unable to dispatch #{task_name(kind)} to the node; retrying.") if job.dispatch_attempts == 1
      hold!
    end

    def fail_state!(reason, code)
      enter_terminal!(VolumeCloneJob::STATE_FAILED, reason: reason, event_code: code)
      :wait
    end

    # Stay put: bump the attempt counter and schedule the next sweep.
    def hold!(attrs = {})
      n = job.attempts + 1
      job.update!(attrs.merge(attempts: n, next_poll_at: Time.now + backoff(n)))
      :wait
    end

    # Yield to the next sweep tick without burning an attempt — this tick simply ran out of
    # its single-agent-operation budget.
    def defer!
      job.update!(next_poll_at: Time.now)
      :wait
    end

    # 5s while we are hot, then 15s, then 30s. Capped at 60s.
    def backoff(attempt)
      seconds = if attempt < 12
        5
      elsif attempt < 30
        15
      else
        30
      end
      [seconds, 60].min.seconds
    end

    # --- gates ---------------------------------------------------------------------------

    # @return [String, nil] why this dispatch must wait, or nil when it may proceed.
    #   NB node availability is checked before the per-node cap purely because the cap needs a
    #   node to count against.
    def closed_gate
      return "another clone is snapshotting the same source volume" if sibling_claim?

      node = job.node
      return "the source volume's node is unavailable" if node.nil? || !node.online?

      unless node_capacity?(node)
        return "node #{node.hostname} is at its concurrent backup/restore limit (#{MAX_CONCURRENT_BORG_PER_NODE})"
      end
      nil
    end

    # Controller-owned claim, NOT an AgentTask lookup: agent_tasks only exists after the 15s
    # changelog poll, so it cannot arbitrate a race that happens inside that window.
    #
    # The claim is a STRICT TOTAL ORDER on id — we yield only to a *lower* id, never to a peer.
    # A symmetric "is any sibling claiming?" test deadlocks: `dispatching_backup` is itself one
    # of SOURCE_CLAIM_STATES, so two jobs that both reach it (the ordinary case — one order
    # cloning two volumes from one source) each see the other as the holder, and neither can
    # escape. Adoption cannot break the tie either, since it needs an `archive_name` that
    # neither deadlocked job will ever produce. With an id order the lowest live claimant
    # always proceeds, and if it terminates it leaves SOURCE_CLAIM_STATES and the next one
    # takes over — so the queue always drains.
    #
    # A nil source_volume_id (source destroyed mid-clone) claims nothing and is claimed by
    # nothing; otherwise every orphaned row would gate every other orphaned row.
    def sibling_claim?
      return false if job.source_volume_id.nil?
      VolumeCloneJob.where(source_volume_id: job.source_volume_id, state: VolumeCloneJob::SOURCE_CLAIM_STATES)
        .where(id: ...job.id)
        .exists?
    end

    # Rows whose node is offline are ignored: a stale `running` row left behind by an agent
    # reinstall would otherwise hold this gate closed forever.
    def node_capacity?(node)
      running = AgentTask.active
        .where(node_id: node.id, name: %w[volume.backup volume.restore])
        .includes(:node)
        .count { |task| task.node&.online? }
      running < MAX_CONCURRENT_BORG_PER_NODE
    end

    # Park on a closed gate. Gated time must NOT consume the state deadline — a sibling
    # holding the same-source gate for a 40 minute backup would otherwise blow the follower's
    # 30 minute dispatch budget and fail it for doing exactly what it was told — so the
    # deadline is kept a full state budget ahead for as long as the gate stays shut. That
    # generosity is inert: entering the next state resets the deadline anyway.
    def gated!(reason)
      # A gate must not consume the state deadline (a follower waiting behind a legitimate
      # 40-minute backup would otherwise be killed by its own 30-minute dispatch budget), but
      # unbounded extension means a permanently-closed gate never times out at all. MAX_GATED_TIME
      # is that backstop: a stale `active` AgentTask row on a live node, or a wedged sibling,
      # eventually fails this clone loudly instead of parking it forever.
      if job.gate_blocked_since && job.gate_blocked_since < MAX_GATED_TIME.ago
        return fail_state!(
          "Gave up after waiting #{MAX_GATED_TIME.inspect} for: #{reason}",
          GATE_EVENT_CODE
        )
      end

      attrs = {}
      attrs[:gate_blocked_since] = Time.now if job.gate_blocked_since.nil?
      attrs[:gate_reason] = reason if job.gate_reason != reason

      budget = VolumeCloneJob::STATE_DEADLINES[job.state]
      if budget
        target = Time.now + budget
        attrs[:state_deadline_at] = target if job.state_deadline_at.nil? || job.state_deadline_at < target
      end

      record_gate_detail(reason)
      hold!(attrs)
    end

    # Re-assert the absolute budget for an awaiting_* state whose deadline went missing.
    #
    # NOT a stall extension, despite what the design called for. `entered_state_at + budget` is
    # already what enter_state! wrote, and it is always <= `Time.now + budget`, so for a row in
    # normal shape this is a no-op — the real bound on awaiting_backup / awaiting_restore is
    # the FIXED 12h / 24h ceiling, regardless of whether the task is alive or its node is up.
    # It earns its keep only on a row that reached the state without enter_state! (see
    # #heal_state_stamps!).
    #
    # DEFERRED, needs a decision: a true stall extension — "fail after N hours with no progress,
    # but let a healthy node keep going up to an absolute ceiling" — needs a stall window that
    # is separate from the ceiling, and picking it too tight would kill slow-but-healthy 10GB
    # backups. The fixed caps are the conservative behaviour and are what ships today.
    def reassert_state_budget!
      budget = VolumeCloneJob::STATE_DEADLINES[job.state]
      return if budget.nil? || job.entered_state_at.nil?
      target = [Time.now + budget, job.entered_state_at + budget].min
      return if job.state_deadline_at && job.state_deadline_at >= target
      job.update!(state_deadline_at: target)
    end

    # --- source resolution ---------------------------------------------------------------

    # @return [String, nil] a sibling's raw archive name we can restore from instead of taking
    #   our own backup of the same source.
    def adoptable_archive
      return nil if job.source_volume_id.nil?
      VolumeCloneJob.where(source_volume_id: job.source_volume_id, state: ADOPTABLE_STATES)
        .where.not(id: job.id)
        .where.not(archive_name: [nil, ""])
        .order(updated_at: :desc)
        .limit(1)
        .pick(:archive_name)
    end

    # A snapshot taken in the last RECENT_ARCHIVE_WINDOW is good enough — reuse it instead of
    # making the customer's node do the work twice.
    #
    # The RAW name is recovered by forward-encoding the projected archive list and matching it
    # against `list_archives`' id, never by Base64-decoding the id back into a name.
    #
    # @return [String, nil]
    def recent_archive_name(source)
      snap = source.latest_archive
      return nil if snap.nil? || snap[:created].nil? || snap[:created] <= RECENT_ARCHIVE_WINDOW.ago
      archives = source.repo_info["archives"]
      return nil unless archives.is_a?(Array)
      archives.detect { |name| Base64.urlsafe_encode64(name.to_s) == snap[:id] }
    end

    # --- events --------------------------------------------------------------------------

    # The umbrella event carries NO `task_id` label and NEVER an AgentTask::EVENT_CODE value:
    # Agent::TaskReconciler#correlated_event would otherwise adopt it as the backup task's
    # event and drive it to `completed` the moment the backup finishes, silently truncating
    # the clone.
    def ensure_umbrella_event!
      return job.event_log if job.event_log

      event = EventLog.new(
        locale: "volumes.clone",
        locale_keys: {volume: job.volume&.label.to_s},
        status: "pending",
        audit: job.audit,
        event_code: UMBRELLA_EVENT_CODE,
        labels: {}
      )
      event.volumes << job.volume if job.volume
      event.deployments << job.deployment if job.deployment
      owner = job.volume&.owner
      event.container_services << owner if owner
      event.save!

      job.update!(event_log_id: event.id, started_at: job.started_at || Time.now)
      event.start!
      event
    end

    # Child backup/restore event: created in the SAME tick as the POST, with its `task_id`
    # label set at creation (never stamped afterwards, never created early — a gated >2h wait
    # would let clean_event_status! cancel a pending one). Agent::TaskReconciler drives it from
    # here on; if a dispatch has to be retried we re-use the event that matches the (stable)
    # task id rather than creating a second one.
    def ensure_child_event!(kind, jid)
      existing = EventLog.where("labels ->> 'task_id' = ?", jid).order(created_at: :desc).first
      return existing if existing

      volume = (kind == :backup) ? job.source_volume : job.volume
      return nil if volume.nil?

      event = EventLog.new(
        locale: task_name(kind),
        locale_keys: {},
        status: "pending",
        audit: job.audit,
        event_code: AgentTask::EVENT_CODE[task_name(kind)],
        labels: {"task_id" => jid}
      )
      event.volumes << volume
      event.deployments << volume.deployment if volume.deployment
      event.container_services << volume.container_service if volume.container_service
      event.save!
      event
    end

    def drive_umbrella_event(new_state, reason, event_code)
      event = job.event_log
      code = event_code.presence || UMBRELLA_EVENT_CODE

      case new_state
      when VolumeCloneJob::STATE_COMPLETED
        detail(code, "Clone completed.")
        event&.done!
      when VolumeCloneJob::STATE_CANCELLED
        detail(code, "Clone cancelled. #{reason}".strip)
        event&.cancel!(reason.presence || "Cancelled")
      else
        detail(code, "Clone failed. #{reason}".strip)
        # Emitted whether or not the event was still drivable — a reaper may have terminated
        # it out from under us, and that must not swallow the failure.
        SystemEvent.create!(
          message: "Volume clone failed (clone job #{job.id})",
          log_level: "warn",
          data: {
            clone_job: job.id,
            volume_id: job.volume_id,
            source_volume_id: job.source_volume_id,
            node_id: job.node_id,
            order_id: job.order_id,
            archive_name: job.archive_name,
            event_log_id: job.event_log_id,
            event_status: event&.status,
            error: reason
          },
          # The per-state failure code, so an operator alert can distinguish "backup failed"
          # from "restore failed". NB a discovering_archive timeout therefore emits two
          # SystemEvents under d41b0aa5c73f9e82 — the specific "never found its snapshot" one
          # from #enforce_deadline! and this one. They carry different messages and both are
          # informative; an alert keyed on that code should expect a pair.
          event_code: code
        )
        event&.fail!(reason.presence || "Clone failed")
      end
    end

    # A failed clone that got as far as taking a snapshot but never learned its name owns an
    # archive it cannot address — surface the leak instead of letting it sit in the customer's
    # borg repo unnoticed. (`owns_snapshot` is only set once the name is known, so the normal
    # cleanup path cannot pick this up.)
    def warn_abandoned_snapshot!(new_state)
      return if new_state == VolumeCloneJob::STATE_COMPLETED
      return if job.backup_dispatched_at.blank? || job.clone_label.blank? || job.archive_name.present?

      SystemEvent.create!(
        message: "Volume clone may have abandoned a snapshot on volume #{job.source_volume&.name || job.source_volume_id}",
        log_level: "warn",
        data: {
          clone_job: job.id,
          source_volume_id: job.source_volume_id,
          clone_label: job.clone_label,
          backup_task_id: job.backup_task_id,
          state: new_state
        },
        event_code: ABANDONED_SNAPSHOT_EVENT_CODE
      )
    end

    # Clones carry their own Audit (never the order's — an extra EventLog on the order audit
    # flips PowerCycleContainerService's topology check and arms fail_process!, which detaches
    # the project's private network), so clone events never render on the order page. This one
    # line is what keeps the order's own forensics usable.
    def record_order_summary(new_state, reason)
      event = job.order&.provision_event
      return if event.nil?

      label = job.volume&.label.presence || "volume #{job.volume_id}"
      line = "[#{Time.now.strftime("%F %T")}] Volume clone #{new_state} for #{label}"
      line += " — #{reason}" if reason.present?
      line += " (clone job #{job.id}#{job.event_log_id ? ", event #{job.event_log_id}" : ""})"
      event.event_details.create!(data: line, event_code: ORDER_EVENT_CODE)
    end

    def detail(code, message)
      event = job.event_log
      return nil if event.nil?
      event.event_details.create!(data: "[#{Time.now.strftime("%F %T")}] #{message}", event_code: code)
    end

    # Exactly one line per distinct gate reason, no matter how many ticks we spend waiting.
    def record_gate_detail(reason)
      event = job.event_log
      return if event.nil?
      line = "Waiting: #{reason}."
      return if event.event_details.where(event_code: GATE_EVENT_CODE, data: line).exists?
      event.event_details.create!(data: line, event_code: GATE_EVENT_CODE)
    end

    # --- outside world (stub points) ------------------------------------------------------

    # Live Docker read (Deployment::Container#built? -> docker_client), not part of the
    # single-agent-operation budget. It never raises — docker_client swallows transport errors
    # and returns nil — so a node blip simply reads as "not built yet", bounded by the
    # awaiting_container deadline.
    def container_built?(volume)
      volume&.owner&.containers&.first&.built?
    end

    # A contended projector pass is a silent no-op (per-node advisory try-lock) and the
    # scheduled 15s poll is the backstop, so a failure here is never fatal — we just try again
    # on the next tick.
    def project_node!(node)
      Agent::ChangelogProjector.new(node).call
      true
    rescue => e
      ExceptionAlertService.new(e, EXCEPTION_EVENT_CODE).perform
      false
    end

    # --- misc -----------------------------------------------------------------------------

    # What the customer is shown when a clone's backup or restore fails: it becomes the
    # "Clone failed. …" line on the umbrella event, the job's `last_error`, the SystemEvent,
    # and the order's provision-event summary.
    #
    # `output` FIRST, matching Agent::TaskReconciler#failure_reason — and the order is the
    # whole point of this method. cs-agent distinguishes a returned error from a soft failure
    # a handler recorded on the progress event, and for the soft kind (which is what every
    # failed backup hook, restore hook and rollback is) it synthesizes the generic literal
    # "task reported failure" into `error` while the real diagnostic — the hook's own stderr,
    # e.g. "postRestoreMysql cleanup returned a non-zero exit code / /mnt/data/backups holds
    # no xtrabackup_checkpoints…" — is in `output`. Reading `error` first therefore replaced
    # every actionable message with a placeholder, leaving the node's log as the only place
    # the cause existed.
    def task_failure_reason(task)
      result = task.result.is_a?(Hash) ? task.result : {}
      result["output"].presence || result["error"].presence || "Task #{task.status}"
    end

    def task_name(kind) = (kind == :backup) ? "volume.backup" : "volume.restore"

    def task_id(kind) = (kind == :backup) ? job.backup_task_id : job.restore_task_id

    def task_id_column(kind) = (kind == :backup) ? :backup_task_id : :restore_task_id

    def dispatched_at(kind) = (kind == :backup) ? job.backup_dispatched_at : job.restore_dispatched_at

    def dispatched_column(kind) = (kind == :backup) ? :backup_dispatched_at : :restore_dispatched_at

    def failure_code(kind) = (kind == :backup) ? BACKUP_FAILED_EVENT_CODE : RESTORE_FAILED_EVENT_CODE

    # Never swallowed into a terminal state: the sweeper force-terminates at
    # MAX_CONSECUTIVE_ERRORS so a deterministically-raising tick still reaches the terminal
    # funnel (and schedules its snapshot cleanup) instead of dying silently here.
    def record_exception(e)
      errors << e.message
      ExceptionAlertService.new(e, EXCEPTION_EVENT_CODE).perform
      return if job.nil?

      job.reload # the tick's transaction rolled back; drop anything it left in memory
      job.with_lock do
        n = job.attempts + 1
        job.update!(
          attempts: n,
          consecutive_errors: job.consecutive_errors + 1,
          last_error: e.message.to_s.truncate(1000),
          next_poll_at: Time.now + backoff(n)
        )
      end
    rescue => inner
      ExceptionAlertService.new(inner, EXCEPTION_EVENT_CODE).perform
      nil
    end
  end
end
