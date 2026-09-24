class CreateVolumeCloneJobs < ActiveRecord::Migration[7.2]
  def change
    # Durable per-volume state machine for project-clone volume restores. Replaces the inline
    # VolumeServices::CloneVolumeService, which ran Timeout+sleep loops (up to ~46 min per
    # volume, serially) inside ProcessOrderWorker on the `default` queue. supervisord sends
    # stopsignal=KILL, so a deploy annihilated that job outright — no bulk_requeue, no retry —
    # and left the order wedged in `processing` forever.
    #
    # One row per TARGET volume; the row is the ONLY durable state. The step worker and the
    # clock sweeper are both stateless and idempotent and serialize on a Postgres row lock
    # (the same idiom as Agent::TaskReconciler#react), so a lost enqueue, a SIGKILL, or a Redis
    # flush costs at most one sweep interval.
    #
    # No FK constraints, consistent with agent_tasks / agent_repositories: a volume or project
    # can be destroyed mid-flight and the machine must tolerate it rather than blow up. The
    # model's associations are `dependent: :nullify` for the same reason — a cascade would
    # delete `owns_snapshot`/`clone_label` while the temporary archive still sits in the
    # SOURCE volume's borg repo (the source normally survives), leaking it permanently.
    create_table :volume_clone_jobs do |t|
      # Nullable ON PURPOSE, and the associations are `dependent: :nullify` to match. A volume
      # can be destroyed mid-clone (VolumeServices::TrashVolumeService#perform calls
      # volume.destroy after the agent-side teardown), and the row must survive that: it still
      # carries owns_snapshot/clone_label, which is the only way to reap the temporary archive
      # sitting in the SOURCE volume's borg repo. It is also what makes CloneStepService's
      # "volume no longer exists" cancellation branch reachable. `null: false` here would make
      # nullify raise NotNullViolation and break volume deletion outright.
      t.bigint :volume_id                       # target volume (freshly provisioned, empty)
      t.bigint :source_volume_id                # volume whose data we clone
      t.bigint :audit_id                        # per-clone Audit (NOT the order's — see below)
      t.bigint :deployment_id
      t.uuid :order_id                          # NB orders.id is a uuid, not a bigint
      t.bigint :node_id                         # pinned at dispatch; the borg repo is node-bound
      t.bigint :event_log_id                    # umbrella `volumes.clone` event

      t.string :state, null: false, default: "pending"
      t.datetime :entered_state_at
      t.datetime :next_poll_at, null: false     # sweeper due-time; the liveness contract
      t.datetime :state_deadline_at

      # Gated time does not count against a state deadline. Without this a sibling holding the
      # same-source gate for a 40-minute 10GB backup would blow the follower's 30-minute
      # dispatch deadline and fail it for doing exactly what it was told.
      t.datetime :gate_blocked_since
      t.string :gate_reason

      t.string :requested_archive                # caller-supplied archive (raw), if any
      t.string :clone_label                      # the label WE asked the agent to create
      t.string :archive_name                     # full raw borg name "<label>-m-<ts>"
      t.boolean :owns_snapshot, null: false, default: false # we created it => we must trash it
      t.datetime :snapshot_trashed_at
      t.integer :cleanup_attempts, null: false, default: 0
      t.datetime :next_cleanup_at

      # Persisted BEFORE the POST; *_dispatched_at is stamped only after create_task returns
      # truthy, so re-entry can tell "never sent" from "sent, then we crashed".
      t.string :backup_task_id
      t.datetime :backup_dispatched_at
      t.string :restore_task_id
      t.datetime :restore_dispatched_at

      t.integer :attempts, null: false, default: 0
      t.integer :dispatch_attempts, null: false, default: 0
      # Forces terminal after N repeating exceptions, so a deterministically-raising tick
      # cannot loop forever without ever reaching the terminal funnel (and its cleanup).
      t.integer :consecutive_errors, null: false, default: 0
      t.text :last_error
      t.datetime :polled_at                      # throttles the on-demand changelog projection
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    # One clone per target volume, ever — makes EnqueueCloneService idempotent under
    # ProcessOrderWorker's retry without application-level locking.
    add_index :volume_clone_jobs, :volume_id, unique: true
    add_index :volume_clone_jobs, :order_id
    add_index :volume_clone_jobs, :deployment_id
    add_index :volume_clone_jobs, :backup_task_id
    add_index :volume_clone_jobs, :restore_task_id
    # The sweeper's due query.
    add_index :volume_clone_jobs, [:state, :next_poll_at]
    # The same-source claim: siblings cloning from one source serialize, and the followers
    # adopt the leader's archive. Controller-owned, because agent_tasks only exists after the
    # 15s changelog poll and cannot arbitrate a race that happens inside that window.
    add_index :volume_clone_jobs, [:source_volume_id, :state]
    # The leaked-snapshot reaper.
    add_index :volume_clone_jobs, [:owns_snapshot, :snapshot_trashed_at, :next_cleanup_at],
      name: "index_volume_clone_jobs_on_snapshot_reap"
  end
end
