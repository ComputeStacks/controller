require "test_helper"
require "minitest/mock"

##
# `perform` returns early in test, before the network check, so these drive the extracted
# retry decision directly.
class ContainerWorkers::ProvisionWorkerTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @container = deployment_containers(:wordpress_1)
    @event = EventLog.create!(
      locale: "container.provision",
      event_code: "3e8b1f0d7c2a9465",
      status: "running"
    )
    @args = [@container.to_global_id.to_s, @event.to_global_id.to_s, "stopped"]
  end

  test "ready lets the build go ahead" do
    with_result(:ready) do
      assert decide(0)
    end
    assert_empty ContainerWorkers::ProvisionWorker.jobs
    assert @event.reload.running?
  end

  test "a retry re-enqueues with backoff, the next attempt, and the original args" do
    [[0, 30], [1, 60], [2, 120]].each do |attempt, backoff|
      Sidekiq::Worker.clear_all
      freeze_time do
        with_result(:retry, "No network.") do
          refute decide(attempt)
        end

        job = ContainerWorkers::ProvisionWorker.jobs.sole
        assert_equal @args + [attempt + 1], job["args"]
        assert_in_delta Time.now.to_f + backoff, job["at"], 1
      end
    end

    assert @event.reload.running?, "the event stays running between retries"
    assert_equal 3, @event.event_details.where(event_code: "17bbda63e54e771f").count
    assert_match(/No network\. Retrying in 30s \(attempt 1\/3\)/, @event.event_details.where(event_code: "17bbda63e54e771f").order(:id).first.data)
  end

  test "a retry with the attempts used up fails the event with the reason" do
    with_result(:retry, "No network.") do
      refute decide(3)
    end

    assert_empty ContainerWorkers::ProvisionWorker.jobs
    assert @event.reload.failed?
    assert_equal "Missing network", @event.state_reason
    assert_match(/No network\./, @event.event_details.find_by(event_code: "61b85fcbf2edef40").data)
  end

  test "failed gives up at once" do
    with_result(:failed, "No project.") do
      refute decide(0)
    end

    assert_empty ContainerWorkers::ProvisionWorker.jobs
    assert @event.reload.failed?
  end

  test "requested_state defaults the same way perform does" do
    @args = @args.first(2)
    with_result(:retry, "No network.") do
      ContainerWorkers::ProvisionWorker.new.send(:network_ready?, @container, @event, @args, "running", 0)
    end
    assert_equal @args + ["running", 1], ContainerWorkers::ProvisionWorker.jobs.sole["args"]
  end

  private

  def decide(attempt)
    ContainerWorkers::ProvisionWorker.new.send(:network_ready?, @container, @event, @args, @args[2], attempt)
  end

  def with_result(result, reason = nil, &)
    fake = Struct.new(:result, :reason) do
      def perform = result
    end.new(result, reason)
    NetworkServices::EnsureContainerNetworkService.stub(:new, fake, &)
  end
end
