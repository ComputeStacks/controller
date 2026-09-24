##
# The controller's local projection of one cs-agent `task` (v3.0.0). Snapshot-upsert
# keyed by the controller-supplied `id` (a UUID we mint, or the agent's reserved
# `volume.trash:<name>`). The readiness reconciler (Agent::TaskReconciler) reacts off
# state transitions here — driving the correlated EventLog — and advances
# `reconciled_status` per transition so each transition fires exactly once.
class AgentTask < ApplicationRecord
  self.primary_key = "id"

  belongs_to :node, optional: true
  belongs_to :audit, optional: true

  ACTIVE_STATUSES = %w[pending running].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze

  # v3 task name -> the controller EventLog `event_code` the reconciler correlates on.
  # These match the retired csevent event_codes 1:1 (handoff §7); the export code is
  # EventLog::BACKUP_EXPORT_EVENT_CODE.
  EVENT_CODE = {
    "volume.backup" => "agent-ad28e9aa1933495f",
    "volume.restore" => "agent-bde07117ae85937d",
    "backup.delete" => "agent-1105683bb0f948c0",
    "backup.export" => "agent-e7c1a9d4b6f20835"
  }.freeze

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }
  # Rows whose latest projected status the reconciler has not yet reacted to.
  scope :needs_reconcile, -> { where("reconciled_status IS DISTINCT FROM status") }

  def active? = ACTIVE_STATUSES.include?(status)

  def terminal? = TERMINAL_STATUSES.include?(status)

  # The EventLog event_code this task maps to (nil for volume.trash — no user-facing event).
  def event_code = EVENT_CODE[name]
end
