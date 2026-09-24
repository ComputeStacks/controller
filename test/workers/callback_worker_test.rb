require "test_helper"
require "webmock"

class CallbackWorkerTest < ActiveSupport::TestCase
  # Scope WebMock to THIS test only — enabling it process-wide (via webmock/minitest)
  # would block the real HTTP that other suites make.
  include WebMock::API

  URL = "https://cb.example/hook".freeze

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!
    CallbackWorker.clear
    @volume = volumes(:mysql)
    @audit = Audit.create!(event: "backup.create", rel_id: @volume.id, rel_model: "Volume")
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def make_event(status)
    event = EventLog.new(locale: "volume.backup", locale_keys: {}, status: status, audit: @audit,
      event_code: "agent-ad28e9aa1933495f")
    event.labels = {"callback_url" => URL, "callback_auth" => "Bearer x"}
    event.volumes << @volume
    event.save!
    event
  end

  def args_for(event, timestamp: Time.now.to_i)
    {
      "timestamp" => timestamp,
      "event_id" => event.id,
      "callback" => {"authorization" => "Bearer x", "url" => URL}
    }
  end

  test "posts success: true for a completed event" do
    event = make_event("completed")
    stub_request(:post, URL).to_return(status: 200, body: "")

    CallbackWorker.new.perform args_for(event)

    assert_requested(:post, URL) do |req|
      assert_equal true, JSON.parse(req.body)["success"]
      true
    end
    assert_equal 0, CallbackWorker.jobs.size
  end

  # The data-only caller shape: Wordpress::InstallPluginWorker
  # (engines/wordpress/app/workers/wordpress/install_plugin_worker.rb:14) pushes a "data"
  # payload with NO "event_id", so `event` is nil and the safe navigation in the guard's
  # `event&.active?` is load-bearing — without it every wordpress plugin-install callback
  # would raise NoMethodError on nil.
  test "posts the supplied data for a caller with no event_id" do
    stub_request(:post, URL).to_return(status: 200, body: "")
    timestamp = Time.now.to_i

    CallbackWorker.new.perform(
      "timestamp" => timestamp,
      "callback" => {"authorization" => "Bearer x", "url" => URL},
      "data" => {"timestamp" => timestamp, "success" => true}
    )

    assert_requested(:post, URL) do |req|
      body = JSON.parse(req.body)
      assert_equal true, body["success"]
      assert_equal timestamp, body["timestamp"]
      true
    end
    assert_equal 0, CallbackWorker.jobs.size
  end

  # The guard: an active event at worker time means the status we would report is not the
  # real outcome (pre-commit read, or an event re-activated by start!). Reporting now would
  # send success: false for work that may have succeeded.
  test "refuses to report on a still-active event, records a SystemEvent, and re-enqueues" do
    event = make_event("running")
    args = args_for(event)

    assert_difference "SystemEvent.count", 1 do
      CallbackWorker.new.perform args
    end

    assert_not_requested :post, URL
    # find_by(event_code:), not SystemEvent.sorted.first — the latter leans on
    # order(created_at: :desc) and is only correct today because there are no
    # system_events fixtures.
    assert_not_nil SystemEvent.find_by(event_code: "4b5ba53233315e32")

    # Assert WHICH job was enqueued, not merely that one was: the guard's 30s delay, and the
    # original args round-tripped intact (a re-enqueue that dropped or mangled args, or used
    # the wrong delay, would otherwise pass).
    assert_equal 1, CallbackWorker.jobs.size
    job = CallbackWorker.jobs.first
    # NB Sidekiq stores "created_at" in milliseconds and "at" in float epoch seconds.
    assert_in_delta 30, job["at"] - (job["created_at"] / 1000.0), 2
    assert_equal [args], job["args"]
  end

  test "does not duplicate the SystemEvent when the deferral repeats within the hour" do
    event = make_event("running")

    assert_difference "SystemEvent.count", 1 do
      CallbackWorker.new.perform args_for(event)
      CallbackWorker.new.perform args_for(event)
    end
    assert_equal 2, CallbackWorker.jobs.size
  end

  # The dedup key must identify the EVENT, not the message text: the message used to embed
  # the current status, so a stuck event moving pending -> running logged a second
  # SystemEvent inside the same hour, contradicting "deduped per event per hour".
  test "does not create a second SystemEvent when the active event's status changes within the hour" do
    event = make_event("pending")

    assert_difference "SystemEvent.count", 1 do
      CallbackWorker.new.perform args_for(event)
      event.update!(status: "running")
      CallbackWorker.new.perform args_for(event)
    end
    assert_equal 2, CallbackWorker.jobs.size
  end

  # Without the cutoff re-check inside the guard, a permanently-active event would
  # re-enqueue itself forever. Giving up is TERMINAL — the callback will never be delivered
  # — so unlike the transient deferral it must leave a durable record behind, not just a
  # Rails.logger line inside a Sidekiq container.
  test "stops re-enqueuing an active event once the 4-hour cutoff has passed and records the give-up" do
    event = make_event("running")
    timestamp = 5.hours.ago.to_i

    assert_difference "SystemEvent.count", 1 do
      CallbackWorker.new.perform args_for(event, timestamp: timestamp)
    end
    assert_not_requested :post, URL
    assert_equal 0, CallbackWorker.jobs.size

    system_event = SystemEvent.find_by(event_code: "9d7928ffd15b3a3a")
    assert_not_nil system_event, "giving up must leave a durable SystemEvent"
    assert_equal "warn", system_event.log_level
    assert_equal @audit.id, system_event.audit_id
    assert_equal event.id, system_event.data["event_id"]
    assert_equal "running", system_event.data["status"]
    assert_equal timestamp, system_event.data["timestamp"]
    # The give-up is its own code, not the transient-deferral one.
    assert_nil SystemEvent.find_by(event_code: "4b5ba53233315e32")
  end
end
