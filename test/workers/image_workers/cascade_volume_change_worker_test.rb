require "test_helper"
require "minitest/mock"

##
# The cascade planner and its children.
#
# CascadeVolumeChangeWorker only plans: it writes the parent event's counters and fans out one
# AttachVolumeToServiceWorker per deployed service. The LAST child to finish is what closes the
# parent event, so the two things that must never break are (a) `expected` is written before
# any child can observe it, and (b) every child finalises exactly once, even when its records
# have vanished or the 2-hour reaper already cancelled the parent.
class ImageWorkers::CascadeVolumeChangeWorkerTest < ActiveSupport::TestCase
  # Stands in for VolumeServices::AttachTemplateVolumeService (exercised in its own test).
  class FakeAttach
    def initialize(result)
      @result = result
    end

    def perform = @result

    def message = "fake #{@result}"
  end

  setup do
    ImageWorkers::AttachVolumeToServiceWorker.clear

    @param = container_image_volume_params(:nginx_webroot) # image nginx -> 2 deployed services
    @event = EventLog.create!(
      locale: "image.cascade_volume",
      locale_keys: {"image" => container_images(:nginx).name},
      event_code: "91c08ca8a3617fbc",
      status: "pending"
    )
  end

  def plan!(param_id = @param.id, event_id = @event.id)
    ImageWorkers::CascadeVolumeChangeWorker.new.perform param_id, event_id
  end

  def child_args = ImageWorkers::AttachVolumeToServiceWorker.jobs.map { |j| j["args"] }

  def details = @event.event_details.reload.map(&:data)

  # --- the planner -----------------------------------------------------------------

  test "enqueues one child per deployed service and leaves the event running" do
    expected_services = @param.container_image.deployed_services.to_a
    assert_equal 2, expected_services.count, "fixture sanity: nginx has two deployed services"

    plan!

    assert_equal expected_services.map { |s| [@param.id, s.id, @event.id] }.sort, child_args.sort
    assert @event.reload.running?, "the last child closes the event, not the planner"
    assert_match(/Dispatched 2 services/, details.last)
  end

  test "writes the counters before any child can be enqueued" do
    observed = []
    recorder = lambda do |*args|
      observed << [args, EventLog.find(@event.id).labels.dup]
      nil
    end

    ImageWorkers::AttachVolumeToServiceWorker.stub(:perform_async, recorder) { plan! }

    assert_equal 2, observed.count
    observed.each do |_args, labels|
      assert_equal 2, labels["expected"],
        "a child that observed expected = 0 would immediately close the parent event"
      assert_equal 0, labels["completed"]
    end
  end

  test "the counters start at zero and are merged onto any existing labels" do
    @event.update! labels: {"callback_url" => "https://example.com/hook"}

    plan!

    labels = @event.reload.labels
    assert_equal 2, labels["expected"]
    assert_equal 0, labels["completed"]
    assert_equal 0, labels["created"]
    assert_equal 0, labels["skipped"]
    assert_equal 0, labels["failed"]
    assert_equal "https://example.com/hook", labels["callback_url"],
      "the planner must not clobber labels it does not own"
  end

  test "refuses a reference volume param" do
    ref = container_image_volume_params(:nginx_mounted)
    assert ref.source_volume.present?, "fixture sanity"

    plan! ref.id

    assert_empty child_args
    assert @event.reload.success?
    assert_match(/references another image's volume/, details.first)
  end

  test "closes the event when the image has no deployed services" do
    param = container_image_volume_params(:es_data)
    assert_empty param.container_image.deployed_services, "fixture sanity"

    plan! param.id

    assert_empty child_args
    assert @event.reload.success?
    assert_match(/No deployed services/, details.first)
  end

  test "does nothing when the volume param or the event is gone" do
    assert_nil plan!(0, @event.id)
    assert_nil plan!(@param.id, 0)
    assert_empty child_args
    assert @event.reload.pending?, "a missing record must not transition the event"
  end

  # --- the children ----------------------------------------------------------------

  # The state the planner leaves behind: counters written, event running, children in flight.
  def preset_counters!(expected)
    @event.update! status: "running", labels: {
      "expected" => expected, "completed" => 0, "created" => 0, "skipped" => 0, "failed" => 0
    }
  end

  def run_child!(results)
    queue = results.dup
    stub = ->(*) { FakeAttach.new(queue.shift) }
    VolumeServices::AttachTemplateVolumeService.stub(:new, stub) do
      @param.container_image.deployed_services.each do |service|
        ImageWorkers::AttachVolumeToServiceWorker.new.perform @param.id, service.id, @event.id
      end
    end
  end

  test "each child advances the counters and only the last one closes the event" do
    preset_counters! 2
    services = @param.container_image.deployed_services.to_a

    VolumeServices::AttachTemplateVolumeService.stub(:new, ->(*) { FakeAttach.new(:created) }) do
      ImageWorkers::AttachVolumeToServiceWorker.new.perform @param.id, services.first.id, @event.id
    end

    assert_equal 1, @event.reload.labels["completed"]
    assert @event.running?, "one child of two must not close the parent"

    VolumeServices::AttachTemplateVolumeService.stub(:new, ->(*) { FakeAttach.new(:skipped) }) do
      ImageWorkers::AttachVolumeToServiceWorker.new.perform @param.id, services.last.id, @event.id
    end

    @event.reload
    assert_equal 2, @event.labels["completed"]
    assert @event.success?, "no failures means the event completes"
    assert_equal "created: 1, skipped: 1, failed: 0", @event.state_reason
    assert_includes details, "created: 1, skipped: 1, failed: 0"
  end

  test "a single failure fails the parent event" do
    preset_counters! 2
    run_child! [:created, :failed]

    @event.reload
    assert @event.failed?
    assert_equal "created: 1, skipped: 0, failed: 1", @event.state_reason
    assert_includes details, "created: 1, skipped: 0, failed: 1"
  end

  test "an all-skipped cascade still completes" do
    preset_counters! 2
    run_child! [:skipped, :skipped]

    assert @event.reload.success?
    assert_equal "created: 0, skipped: 2, failed: 0", @event.state_reason
  end

  # Without this the counter stays short and the parent hangs until Events::EventPurger
  # cancels it two hours later.
  test "a child whose service has vanished still finalises the counter" do
    preset_counters! 1

    ImageWorkers::AttachVolumeToServiceWorker.new.perform @param.id, 0, @event.id

    @event.reload
    assert_equal 1, @event.labels["completed"]
    assert_equal 1, @event.labels["skipped"]
    assert @event.success?
    assert_match(/no longer exists/, details.first)
  end

  test "a child with no event at all is a no-op" do
    assert_nil ImageWorkers::AttachVolumeToServiceWorker.new.perform(@param.id, @event.container_services.first&.id || 1, 0)
  end

  # Events::EventPurger#clean_event_status! update_all's stale running events to `cancelled`,
  # after which done!/fail! return false silently. The summary detail is written before the
  # terminal transition precisely so it survives that.
  test "the summary detail survives a parent the reaper already cancelled" do
    preset_counters! 1
    @event.update_columns(status: "cancelled")

    run_child! [:created]

    assert_equal "cancelled", @event.reload.status
    assert_includes details, "created: 1, skipped: 0, failed: 0"
  end

  test "an unexpected result symbol is counted as a failure rather than dropped" do
    preset_counters! 1
    services = @param.container_image.deployed_services.to_a

    VolumeServices::AttachTemplateVolumeService.stub(:new, ->(*) { FakeAttach.new(nil) }) do
      ImageWorkers::AttachVolumeToServiceWorker.new.perform @param.id, services.first.id, @event.id
    end

    @event.reload
    assert_equal 1, @event.labels["failed"]
    assert @event.failed?
  end

  # --- queue placement --------------------------------------------------------------

  # These provision real volumes on remote nodes: deployment-domain work served by
  # worker_deployments. The previous implementation sat on `default`, which worker_system does
  # serve — so it ran, just in the wrong pool for node provisioning work.
  test "both workers run on a deployments queue" do
    assert_equal "dep_low", ImageWorkers::CascadeVolumeChangeWorker.sidekiq_options["queue"]
    assert_equal "dep_low", ImageWorkers::AttachVolumeToServiceWorker.sidekiq_options["queue"]
    assert_equal false, ImageWorkers::CascadeVolumeChangeWorker.sidekiq_options["retry"]
    assert_equal false, ImageWorkers::AttachVolumeToServiceWorker.sidekiq_options["retry"]
  end
end
