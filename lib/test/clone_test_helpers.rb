# Fixture builders for the async volume-clone state machine (VolumeCloneJob +
# VolumeServices::CloneStepService + VolumeWorkers::Clone*).
#
# `include CloneTestHelpers` in an ActiveSupport::TestCase subclass. Everything here is
# built inline because there are NO fixtures for agent_tasks, agent_repositories,
# event_logs, audits, or orders — only volumes/nodes/deployments/container_services/
# containers, which these helpers build on top of.
#
#     class MyCloneTest < ActiveSupport::TestCase
#       include CloneTestHelpers
#
#       test "..." do
#         seed_archives volumes(:mysql), [archive_name("clone-42")]
#         job = make_clone_job(state: VolumeCloneJob::STATE_DISCOVERING_ARCHIVE)
#         ...
#       end
#     end
#
# Note `test/fixtures/volumes.yml` regenerates `name:` as a fresh SecureRandom.uuid on every
# load, so these helpers always read `volume.name` — never hardcode it, and never key an
# AgentRepository/AgentTask on a literal.
module CloneTestHelpers
  # Event codes frozen by the clone contract. Wave 2 asserts against these rather than
  # re-typing 16 hex digits per test. The umbrella code is deliberately NOT one of
  # AgentTask::EVENT_CODE's values — if it were, Agent::TaskReconciler#correlated_event would
  # adopt the umbrella event as the backup task's own and drive it terminal early.
  CLONE_EVENT_CODES = {
    umbrella: "5c1e7a3f9b024d68",
    archive_never_appeared: "d41b0aa5c73f9e82",
    deadline_exceeded: "a80f5d1c46e3b927",
    gate_waiting: "c17e34b8d5a09f26",
    abandoned_snapshot: "0b93af5162c7de84",
    tick_exception: "b4e181611d7c5423",
    container_never_built: "53a075e943b51b72",
    source_gone: "9a69eb920764c1da",
    backup_failed: "7704f466b97ac18c",
    restore_failed: "9858861ab2912307",
    creating_snapshot: "67e93090ab029cf5",
    restoring_snapshot: "79e6e2d3860d1806",
    order_restoring_background: "3f7c2b90a15de846"
  }.freeze

  # The umbrella event's locale (config/locales/events/en.yml -> events.messages.volumes.clone,
  # "Cloning volume %{volume}").
  CLONE_LOCALE = "volumes.clone"

  # The agent stamps borg archives "<label>-m-<timestamp>" with a zone-less ISO8601 second
  # (Volumes::ConsulVolume#list_archives re-parses it as `Time.parse("#{ts} UTC")`).
  ARCHIVE_TS_FORMAT = "%Y-%m-%dT%H:%M:%S"

  # --- agent client ----------------------------------------------------------------

  # Run `block` with Agent::Client replaced by a FakeAgentClient for both entry points
  # (`.for_node`, used by every DOWN call, and `.new`, used by project-scoped callers).
  #
  # @param fake [FakeAgentClient]
  # @return the block's return value
  def with_fake_agent(fake = FakeAgentClient.new)
    require "minitest/mock"
    Agent::Client.stub(:for_node, fake) do
      Agent::Client.stub(:new, fake) do
        yield fake
      end
    end
  end

  # The real Agent::Client#create_task refuses to POST to a node whose desired-state was
  # never backfilled. The nodes fixture leaves `datachannel_backfilled_at` nil, so any test
  # exercising the REAL client (rather than FakeAgentClient) must stamp it first.
  # @return [Node]
  def backfill_node!(node = nodes(:testone), at: Time.now)
    node.update_columns(datachannel_backfilled_at: at)
    node
  end

  # --- archive names ---------------------------------------------------------------

  # A parseable archive name in the agent's real shape, e.g. "clone-42-m-2026-07-30T12:00:00".
  # @param label [String] the label the controller asked for
  # @param at [Time] the suffix timestamp the agent chose
  # @return [String]
  def archive_name(label, at: Time.now)
    "#{label}-m-#{at.utc.strftime(ARCHIVE_TS_FORMAT)}"
  end

  # The agent's scheduled-backup shape, "auto-<ts>-m-<ts>" (label "auto").
  # @return [String]
  def auto_archive_name(at: Time.now)
    ts = at.utc.strftime(ARCHIVE_TS_FORMAT)
    "auto-#{ts}-m-#{ts}"
  end

  # An archive name #list_archives CANNOT date: no "auto-" prefix and no "-m-" separator, so
  # it yields {id:, label:} with NO :created key. One of these in a repo is what made a naive
  # `sort_by { |a| a[:created] }` raise "comparison of NilClass with Time failed".
  # @return [String]
  def unparseable_archive_name(label = "manual-2020-01-01")
    raise ArgumentError, "#{label.inspect} is parseable" if label.include?("-m-") || label.include?("auto-")
    label
  end

  # The other half of the same regression: the name SPLITS correctly on "-m-" but the
  # timestamp is rejected by Time.parse, so #list_archives rescues into the label-only shape
  # and again omits :created.
  # @return [String]
  def bad_timestamp_archive_name(label = "clone-broken")
    "#{label}-m-not-a-timestamp"
  end

  # --- agent_repositories (what Volume#repo_info projects) --------------------------

  # Create or replace the projected borg repo row for `volume` with exactly `names`.
  #
  # Deliberately does NOT call `volume.reset_repo_info!` — `repo_info` memoizes, and whether
  # a caller drops that memo is the thing under test. Reset explicitly when you want the
  # object to observe the write.
  #
  # @param volume [Volume]
  # @param names [Array<String>] raw borg archive names, oldest first (the agent's order;
  #   #list_archives reverses it, so the LAST element is "newest")
  # @return [AgentRepository]
  def seed_archives(volume, names = [], size_on_disk: 100, total_size: 250, node: nodes(:testone))
    repo = AgentRepository.find_or_initialize_by(name: volume.name)
    repo.assign_attributes(
      archives: Array(names),
      size_on_disk: size_on_disk,
      total_size: total_size,
      node_id: node&.id,
      agent_updated_at: Time.now
    )
    repo.save!
    repo
  end

  # Append one archive to an already-seeded repo, simulating a changelog pass that lands
  # AFTER something already read `repo_info`. The root-cause regression test is:
  #
  #     seed_archives(vol, [])
  #     vol.repo_info                      # warms the memo
  #     append_archive(vol, archive_name("clone-1"))
  #     assert_nil vol.find_archive_by_label("clone-1")   # stale memo — the production bug
  #     assert vol.reset_repo_info!.find_archive_by_label("clone-1")
  #
  # Also does NOT touch the memo, for the same reason as #seed_archives.
  #
  # @return [AgentRepository]
  def append_archive(volume, name, **attrs)
    repo = AgentRepository.find_by(name: volume.name)
    existing = repo ? Array(repo.archives) : []
    seed_archives(volume, existing + [name], **attrs)
  end

  # --- agent_tasks -----------------------------------------------------------------

  # Build an AgentTask row, mirroring `make_task` in test/services/agent/task_reconciler_test.rb.
  # There is no fixture file for agent_tasks; the primary key is the controller-supplied id.
  #
  # @param volume [Volume, String] a Volume (its #name is used) or a raw volume name
  # @param project_id [String, nil] defaults to the volume's deployment id as a String
  # @return [AgentTask]
  def make_agent_task(id: SecureRandom.uuid, name: "volume.backup", status: "pending",
    volume: volumes(:mysql), node: nodes(:testone), audit_id: nil, project_id: :from_volume,
    result: nil, reconciled_status: nil, changelog_seq: nil)
    vol = volume.is_a?(Volume) ? volume : nil
    volume_name = vol ? vol.name : volume.to_s
    pid = (project_id == :from_volume) ? vol&.deployment&.id.to_s : project_id

    AgentTask.create!(
      id: id,
      name: name,
      status: status,
      audit_id: audit_id,
      volume: volume_name,
      node_id: node&.id,
      project_id: pid,
      result: result,
      reconciled_status: reconciled_status,
      changelog_seq: changelog_seq
    )
  end

  # --- audits / event logs ---------------------------------------------------------

  # Each clone job gets its OWN audit (rel_model "Volume", event "restored") — never the
  # order's audit. An extra EventLog on the order's audit flips PowerCycleContainerService's
  # `audit.event_logs.count == 1` topology check and arms ProcessOrderService#fail_process!,
  # which detaches the project's private network.
  # @return [Audit]
  def make_clone_audit(volume = volumes(:wordpress_web), event: "restored", user: nil)
    Audit.create!(event: event, rel_id: volume.id, rel_model: "Volume", user: user)
  end

  # The umbrella "Cloning volume X" event.
  #
  # It carries NO "task_id" label and NOT an AgentTask::EVENT_CODE value, on purpose:
  # Agent::TaskReconciler#correlated_event matches on audit_id + event_code, and would
  # otherwise adopt this event as the backup task's and drive it to completed the moment the
  # backup finished — truncating the clone.
  #
  # @return [EventLog]
  def make_clone_event(volume: volumes(:wordpress_web), audit: nil, status: "pending",
    event_code: CLONE_EVENT_CODES[:umbrella], labels: {})
    audit ||= make_clone_audit(volume)
    event = EventLog.new(
      locale: CLONE_LOCALE,
      locale_keys: {volume: volume.label},
      status: status,
      audit: audit,
      event_code: event_code
    )
    event.labels = labels if labels.present?
    event.volumes << volume
    event.deployments << volume.deployment if volume.deployment
    cs = volume.container_service
    event.container_services << cs if cs
    event.save!
    event
  end

  # A backup/restore CHILD event, in the shape CloneStepService must create in the same tick
  # as the POST: the correlating "task_id" label is set AT CREATION, never stamped afterwards.
  #
  # @param kind [String] "volume.backup" or "volume.restore"
  # @return [EventLog]
  def make_clone_child_event(volume: volumes(:wordpress_web), audit: nil, task_id: SecureRandom.uuid,
    kind: "volume.backup", status: "pending")
    audit ||= make_clone_audit(volume)
    locale = (kind == "volume.restore") ? "snapshots.restore" : "volume.backup"
    event = EventLog.new(
      locale: locale,
      locale_keys: {},
      status: status,
      audit: audit,
      event_code: AgentTask::EVENT_CODE.fetch(kind)
    )
    event.labels = {"task_id" => task_id}
    event.volumes << volume
    event.deployments << volume.deployment if volume.deployment
    event.save!
    event
  end

  # --- volume_clone_jobs -----------------------------------------------------------

  # Build a VolumeCloneJob in `state` with a consistent set of timestamps.
  #
  # `volume_id` and `source_volume_id` are NOT NULL at the DB level (the model's
  # `optional: true` only relaxes the presence validation), so both always get a value. The
  # defaults clone volumes(:mysql) -> volumes(:wordpress_web); both live on nodes(:testone)
  # in deployments(:project_test).
  #
  # By default an Audit and the umbrella EventLog are built and wired in; pass
  # `audit: nil, event_log: nil` for a bare row, or pass your own.
  #
  # `entered_state_at` / `state_deadline_at` are derived from VolumeCloneJob::STATE_DEADLINES
  # so a freshly built job is never accidentally `overdue`. Override any column via `attrs`
  # (e.g. `archive_name:`, `backup_task_id:`, `owns_snapshot:`, `consecutive_errors:`).
  #
  # @return [VolumeCloneJob]
  def make_clone_job(volume: volumes(:wordpress_web), source_volume: volumes(:mysql),
    state: VolumeCloneJob::STATE_PENDING, node: nodes(:testone), deployment: :from_volume,
    order: nil, audit: :auto, event_log: :auto, next_poll_at: nil, entered_state_at: nil,
    state_deadline_at: :auto, **attrs)
    now = Time.now
    audit = make_clone_audit(volume) if audit == :auto
    if event_log == :auto
      event_log = make_clone_event(volume: volume, audit: audit)
    end
    deployment = volume.deployment if deployment == :from_volume
    entered = entered_state_at || now
    if state_deadline_at == :auto
      budget = VolumeCloneJob::STATE_DEADLINES[state]
      state_deadline_at = budget ? entered + budget : nil
    end

    VolumeCloneJob.create!({
      volume: volume,
      source_volume: source_volume,
      state: state,
      node: node,
      deployment: deployment,
      order: order,
      audit: audit,
      event_log: event_log,
      entered_state_at: entered,
      state_deadline_at: state_deadline_at,
      next_poll_at: next_poll_at || now
    }.merge(attrs))
  end

  # An Order to hang a clone job off, for the order-level "restoring in background" path.
  # There is no orders fixture; the table's PK is a uuid default.
  #
  # `order_data` defaults to `{}` on purpose: Order's before_save `generate_details` does
  # `order_data.empty?` unguarded, so a nil order_data raises NoMethodError on create.
  # Pass a real `{"raw_order" => [...]}` when the test needs the summary machinery.
  #
  # @return [Order]
  def make_clone_order(deployment: deployments(:project_test), user: users(:admin),
    status: "open", order_data: {})
    Order.create!(deployment: deployment, user: user, status: status,
      ip_addr: "127.0.0.1", order_data: order_data)
  end

  # --- assorted --------------------------------------------------------------------

  # Make `volume` look like it has no online node (active_node -> nil, dispatch refused).
  # @return [Node]
  def take_node_offline!(node = nodes(:testone))
    node.update_columns(disconnected: true)
    node
  end
end
