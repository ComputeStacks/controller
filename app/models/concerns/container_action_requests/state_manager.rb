module ContainerActionRequests
  # State machine for a projected container action. Plain-string status column +
  # guarded transitions (mirrors Events::StateManager — no enum/AASM in this repo).
  #
  #   received ──dispatch!──▶ dispatching ──▶ done            (handler accepted)
  #                                        ├─▶ dead            (permanent failure)
  #                                        └─▶ failed ──▶ (retry) dispatching …
  #   received/failed ──▶ superseded  (coalesced away)
  #   received ──▶ unhandled | rejected  (no handler / not owned / unknown project)
  #
  # `dispatch!` atomically CLAIMS a row (a conditional UPDATE) so concurrent workers
  # can't both proceed — at-most-once *claim*. The side effect is still at-least-once
  # on a mid-dispatch crash (the row is reaped via stuck? and retried), so registered
  # handlers MUST be idempotent.
  module StateManager
    extend ActiveSupport::Concern

    MAX_ATTEMPTS = 8
    STUCK_TIMEOUT = 5.minutes
    ACTIVE_STATUSES = %w[received failed].freeze
    TERMINAL_STATUSES = %w[done dead rejected unhandled superseded].freeze

    included do
      # Rows ready to (re)dispatch: fresh, or a failed row whose backoff elapsed.
      scope :actionable, -> {
        where("status = 'received' OR (status = 'failed' AND (next_attempt_at IS NULL OR next_attempt_at <= ?))", Time.current)
      }
    end

    def received? = status == "received"

    def dispatching? = status == "dispatching"

    def done? = status == "done"

    def failed? = status == "failed"

    def dead? = status == "dead"

    def rejected? = status == "rejected"

    def unhandled? = status == "unhandled"

    def superseded? = status == "superseded"

    def terminal? = TERMINAL_STATUSES.include?(status)

    # A dispatch that never reported back (worker died mid-call).
    def stuck?
      dispatching? && updated_at < STUCK_TIMEOUT.ago
    end

    # Atomically claim the row for dispatch. Returns true ONLY for the caller that
    # flips it -> dispatching; concurrent callers get 0 rows and false. Honors
    # next_attempt_at (same predicate as the `actionable` scope) so a duplicate
    # worker can't claim a failed row before its backoff has elapsed.
    # @return [Boolean]
    def dispatch!
      won = self.class.where(id: id)
        .where("status = 'received' OR (status = 'failed' AND (next_attempt_at IS NULL OR next_attempt_at <= :t))", t: Time.current)
        .update_all(status: "dispatching", dispatched_at: Time.current, updated_at: Time.current)
      won == 1 && reload && true
    end

    # @return [Boolean]
    def complete!(result = nil)
      return false unless dispatching?
      update(status: "done", result: result, state_reason: nil)
    end

    # Permanent failure the handler reported (e.g. a bad request / 4xx). Alertable.
    # @return [Boolean]
    def kill!(reason)
      update(status: "dead", state_reason: reason)
    end

    # Not actionable by us: no registered handler's engine owns it, or the project
    # is gone. Terminal and benign (no alert). @return [Boolean]
    def reject!(reason)
      update(status: "rejected", state_reason: reason)
    end

    # No handler registered for this action_type (e.g. the owning engine isn't
    # loaded). Terminal. @return [Boolean]
    def unhandled!(reason = nil)
      update(status: "unhandled", state_reason: reason)
    end

    # Coalesced away by a newer/broader action for the same project. @return [Boolean]
    def supersede!(by:)
      return false unless ACTIVE_STATUSES.include?(status)
      update(status: "superseded", state_reason: "superseded by #{by}")
    end

    # Transient failure: back off and retry, or give up permanently after
    # MAX_ATTEMPTS. Backoff (not the poll cadence) gates the next attempt via the
    # `actionable` scope. @return [Boolean]
    def retry_later!(reason)
      return false unless dispatching?
      self.attempts += 1
      if attempts >= MAX_ATTEMPTS
        kill!("giving up after #{attempts} attempts: #{reason}")
      else
        backoff = [30 * (2**(attempts - 1)), 3600].min
        update(status: "failed", state_reason: reason, attempts: attempts, next_attempt_at: Time.current + backoff.seconds)
      end
    end
  end
end
