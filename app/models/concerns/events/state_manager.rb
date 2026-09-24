module Events
  module StateManager
    extend ActiveSupport::Concern

    included do
      scope :active, -> { where "status = 'pending' OR status = 'running'" }
      scope :running, -> { where status: "running" }
      scope :pending, -> { where status: "pending" }
      scope :failed, -> { where status: "failed" }
    end

    # @return [Boolean]
    def pending?
      status == "pending"
    end

    # @return [Boolean]
    def running?
      status == "running"
    end

    # @return [Boolean]
    def cancelled?
      status == "cancelled"
    end

    # @return [Boolean]
    def active?
      running? || pending?
    end

    # @return [Boolean]
    def done?
      !active?
    end

    # @return [Boolean]
    def success?
      status == "completed"
    end

    # @return [Boolean]
    def failed?
      status == "failed"
    end

    # @return [Boolean]
    def pending!
      return true if pending?
      update status: "pending"
    end

    # @return [Boolean]
    def start!(msg = nil)
      return false if failed? || cancelled?
      msg.blank? ? update(status: "running") : update(status: "running", state_reason: msg)
    end

    # @return [Boolean]
    def done!(msg = nil)
      return false unless active?
      msg.blank? ? update(status: "completed") : update(status: "completed", state_reason: msg)
      perform_callback_reply!
    end

    # @return [Boolean]
    def cancel!(msg)
      return false unless active?
      update status: "cancelled", state_reason: msg
      perform_callback_reply!
    end

    # @return [Boolean]
    def fail!(msg)
      return false unless active?
      update status: "failed", state_reason: msg
      perform_callback_reply!
    end

    # Handle any callbacks added to this event
    #
    # NB the `true` return no longer means "enqueued" — since the push is deferred past
    # COMMIT (below) it may only mean "registered to be enqueued when this transaction
    # commits", and it stays `true` even for a transaction that later rolls back and sends
    # nothing. Don't build anything on the return value; it is kept only because the
    # terminal transitions return it.
    def perform_callback_reply!
      return if labels.empty?
      return if labels["callback_url"].blank?

      d = {
        "timestamp" => Time.now.to_i,
        "event_id" => id,
        "callback" => {
          "authorization" => labels["callback_auth"],
          "url" => labels["callback_url"]
        }
      }

      # Defer the enqueue past COMMIT. CallbackWorker re-reads this EventLog on another
      # connection and derives `success` from the persisted status, so pushing from inside
      # a transaction (e.g. Agent::TaskReconciler#react drives terminal transitions inside
      # `task.with_lock`) lets the worker read pre-commit state and report `success: false`
      # for work that actually succeeded — which the receiver records permanently. If the
      # transaction rolls back, the block never runs and no callback is sent at all (the
      # transition retries instead). With no open transaction it runs immediately, so every
      # other caller keeps today's behavior.
      #
      # ACCEPTED RISK: deferring moves the push after the point of no return. If the
      # deferred `perform_async` itself fails (Redis down), the transition has already
      # committed and the callback is simply lost — and the raise only reaches an operator
      # via Sentry when SENTRY_CONFIGURED is set; otherwise it degrades to a log line.
      #
      # This is the same mechanism Sidekiq 8 uses for this problem —
      # Sidekiq::TransactionAwareClient#initialize is literally
      # ActiveRecord.method(:after_all_transactions_commit)
      # (sidekiq/transaction_aware_client.rb:12). We do it here rather than flipping the
      # global `Sidekiq.transactional_push!` because that would move uniqueness-lock
      # acquisition (SidekiqUniqueJobs client middleware) from pre- to post-commit for every
      # perform_async in the app — an unvalidated surface for a targeted bugfix.
      #
      # NB the `d` hash (incl. Time.now.to_i) is built here on purpose: the timestamp feeds
      # CallbackWorker's 4-hour cutoff and retry buckets and should stamp the transition.
      ActiveRecord.after_all_transactions_commit { CallbackWorker.perform_async d }
      true
    end
  end
end
