require "test_helper"

##
# Events::StateManager#perform_callback_reply! defers the Sidekiq push with
# ActiveRecord.after_all_transactions_commit so an in-transaction transition cannot make
# CallbackWorker read pre-commit state. These tests pin the OTHER half of that contract —
# the ~6 callers that transition with no enclosing transaction must still enqueue
# immediately, exactly as before the fix. (Nothing else in the suite proves that: a
# deferral that only enqueued when a transaction happened to be open would pass every
# reconciler test, since those all run inside `with_lock`.)
class Events::StateManagerTest < ActiveSupport::TestCase
  setup do
    CallbackWorker.clear
    @volume = volumes(:mysql)
    @audit = Audit.create!(event: "backup.create", rel_id: @volume.id, rel_model: "Volume")
  end

  def make_event(callback: true)
    event = EventLog.new(locale: "volume.backup", locale_keys: {}, status: "pending",
      audit: @audit, event_code: "agent-ad28e9aa1933495f")
    event.labels = {"callback_url" => "https://cb.example/hook", "callback_auth" => "Bearer x"} if callback
    event.volumes << @volume
    event.save!
    event
  end

  # NB "no enclosing transaction" means no *explicit* one: the transactional-fixture
  # transaction is non-joinable, so all_open_transactions is empty here and the deferred
  # block runs inline — the same situation as production for these callers.
  test "done! enqueues the callback immediately when no transaction is open" do
    event = make_event

    assert event.done!
    assert_equal 1, CallbackWorker.jobs.size, "a caller with no open transaction must enqueue immediately"
    assert_equal event.id, CallbackWorker.jobs.first["args"].first["event_id"]
    assert event.reload.success?
  end

  test "fail! enqueues the callback immediately when no transaction is open" do
    event = make_event

    assert event.fail!("nope")
    assert_equal 1, CallbackWorker.jobs.size
    assert event.reload.failed?
  end

  test "cancel! enqueues the callback immediately when no transaction is open" do
    event = make_event

    assert event.cancel!("nevermind")
    assert_equal 1, CallbackWorker.jobs.size
    assert_equal "cancelled", event.reload.status
  end

  test "no callback_url means no enqueue at all" do
    event = make_event(callback: false)

    assert_nil event.done!
    assert_equal 0, CallbackWorker.jobs.size
  end
end
