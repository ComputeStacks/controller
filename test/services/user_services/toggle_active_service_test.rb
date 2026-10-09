require "test_helper"
require "minitest/mock"

class UserServices::ToggleActiveServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @containers = @user.deployed_containers.to_a + @user.sftp_containers.to_a
    UserWorkers::ReconcileSuspensionWorker.jobs.clear
  end

  # Replaces PowerCycleContainerService with a recorder. `accept` decides per call whether
  # the action is accepted (its event left pending) or refused (canceled).
  def with_recorded_power_cycles(accept: ->(_c, _a) { true })
    calls = []
    fake_new = lambda do |container, action, audit|
      Struct.new(:event) do
        define_method(:perform) do
          calls << [container, action, audit]
          code = (action == "stop") ? "0b264bd661e2d449" : "f59498e7717c7106"
          self.event = EventLog.create!(locale: "container.#{action}", status: accept.call(container, action) ? "pending" : "cancelled",
            event_code: code, audit: audit)
          container.is_a?(Deployment::Sftp) ? event.sftp_containers << container : event.containers << container
          true
        end
      end.new
    end
    PowerCycleContainerService.stub(:new, fake_new) { yield }
    calls
  end

  def suspension_event
    UserServices::ToggleActiveService.toggle_events(@user).where(locale: "users.inactive").order(:id).last
  end

  test "suspend stops running containers, each on its own event, and reactivate restarts only those" do
    assert @containers.size >= 2, "fixture user needs two containers"
    kept_stopped = @containers.first
    kept_stopped.update_columns(req_state: "stopped")
    running = @containers.drop(1)
    running.each { |c| c.update_columns(req_state: "running") }

    suspend_calls = with_recorded_power_cycles { @user.update!(active: false) }
    assert_equal running.map(&:global_id).sort, suspend_calls.map { |c| c[0].global_id }.sort
    assert_equal ["stop"], suspend_calls.map { |c| c[1] }.uniq
    toggle_audits = UserServices::ToggleActiveService.toggle_events(@user).pluck(:audit_id)
    suspend_calls.each { |(_, _, audit)| refute_includes toggle_audits, audit.id }
    assert_empty UserWorkers::ReconcileSuspensionWorker.jobs

    resume_calls = with_recorded_power_cycles { @user.update!(active: true) }
    assert_equal running.map(&:global_id).sort, resume_calls.map { |c| c[0].global_id }.sort
    assert_equal ["start"], resume_calls.map { |c| c[1] }.uniq
  end

  test "reactivating a user suspended before suspension stopped anything starts nothing" do
    @user.update_columns(active: false)
    calls = with_recorded_power_cycles { @user.update!(active: true) }
    assert_empty calls
  end

  test "the suspension is recorded even when stopping fails partway" do
    @containers.each { |c| c.update_columns(req_state: "running") }
    boom = ->(*) { raise "boom" }
    PowerCycleContainerService.stub(:new, boom) { @user.update!(active: false) }
    assert_equal "failed", suspension_event.status
    assert_equal @containers.map { |c| c.global_id.to_s }.sort,
      suspension_event.labels["suspended_containers"].sort
    assert_equal 1, UserWorkers::ReconcileSuspensionWorker.jobs.size
  end

  test "a refused stop is retried until the container is stopped" do
    target = @containers.first
    target.update_columns(req_state: "running")
    (@containers - [target]).each { |c| c.update_columns(req_state: "stopped") }
    with_recorded_power_cycles(accept: ->(_c, _a) { false }) { @user.update!(active: false) }
    job = UserWorkers::ReconcileSuspensionWorker.jobs.last
    assert_equal [@user.id, suspension_event.id, 1], job["args"]

    retried = with_recorded_power_cycles { UserWorkers::ReconcileSuspensionWorker.new.perform(*job["args"]) }
    assert_equal [[target, "stop"]], retried.map { |c| c[0..1] }

    target.update_columns(req_state: "stopped")
    EventLog.where(status: "pending").update_all(status: "completed")
    UserWorkers::ReconcileSuspensionWorker.jobs.clear
    none = with_recorded_power_cycles { UserWorkers::ReconcileSuspensionWorker.new.perform(@user.id, suspension_event.id, 2) }
    assert_empty none
    assert_empty UserWorkers::ReconcileSuspensionWorker.jobs
  end

  test "reconcile stands down once a newer suspend or reactivate exists" do
    @containers.each { |c| c.update_columns(req_state: "running") }
    with_recorded_power_cycles(accept: ->(_c, _a) { false }) { @user.update!(active: false) }
    first = suspension_event
    with_recorded_power_cycles { @user.update!(active: true) }
    calls = with_recorded_power_cycles { UserWorkers::ReconcileSuspensionWorker.new.perform(@user.id, first.id, 1) }
    assert_empty calls
  end

  test "suspending while a reactivation is still starting a container stops it too" do
    target = @containers.first
    target.update_columns(req_state: "running")
    with_recorded_power_cycles { @user.update!(active: false) }
    target.update_columns(req_state: "stopped")
    with_recorded_power_cycles { @user.update!(active: true) } # start queued, not yet run
    calls = with_recorded_power_cycles { @user.update!(active: false) }
    assert_includes calls.map(&:first), target
  end

  test "suspending again while a reactivation start is still being retried records it" do
    target = @containers.first
    target.update_columns(req_state: "running")
    with_recorded_power_cycles { @user.update!(active: false) }
    target.update_columns(req_state: "stopped")
    # The reactivation's start is refused (node offline): no active event, still stopped.
    with_recorded_power_cycles(accept: ->(_c, _a) { false }) { @user.update!(active: true) }
    calls = with_recorded_power_cycles { @user.update!(active: false) }
    assert_includes calls.map(&:first), target
  end

  test "a container the user stopped after reactivation stays out of the next suspension" do
    target = @containers.first
    target.update_columns(req_state: "running")
    with_recorded_power_cycles { @user.update!(active: false) }
    with_recorded_power_cycles { @user.update!(active: true) }
    user_stop = EventLog.create!(locale: "container.stop", status: "completed", event_code: "0b264bd661e2d449")
    target.is_a?(Deployment::Sftp) ? user_stop.sftp_containers << target : user_stop.containers << target
    target.update_columns(req_state: "stopped")
    calls = with_recorded_power_cycles { @user.update!(active: false) }
    refute_includes calls.map(&:first), target
  end

  test "a start that lands after the suspension does not switch billing back on" do
    container = @user.deployed_containers.detect(&:subscription)
    skip "fixture user has no billed container" if container.nil?
    @user.update_columns(active: false)
    container.subscription.update_columns(active: false)
    event = EventLog.create!(locale: "container.start", status: "running", event_code: "f59498e7717c7106")
    docker = Struct.new(:x) { def start = true }.new
    container.stub(:docker_client_with_event, docker) do
      container.stub(:power_cycle_response, true) { container.start!(event) }
    end
    refute container.subscription.reload.active
  end

  test "reconcile waits on a disconnected node without leaving events behind" do
    target = @containers.first
    target.update_columns(req_state: "running")
    (@containers - [target]).each { |c| c.update_columns(req_state: "stopped") }
    with_recorded_power_cycles(accept: ->(_c, _a) { false }) { @user.update!(active: false) }
    target.node.update_columns(disconnected: true)
    UserWorkers::ReconcileSuspensionWorker.jobs.clear
    calls = with_recorded_power_cycles { UserWorkers::ReconcileSuspensionWorker.new.perform(@user.id, suspension_event.id, 1) }
    assert_empty calls
    assert_equal [[@user.id, suspension_event.id, 2]], UserWorkers::ReconcileSuspensionWorker.jobs.map { |j| j["args"] }
  end

  test "a toggle that refuses and then fails schedules one reconcile" do
    @containers.each { |c| c.update_columns(req_state: "running") }
    boom = ->(*) { raise "boom" }
    with_recorded_power_cycles(accept: ->(_c, _a) { false }) do
      ProcessAppEventWorker.stub(:perform_async, boom) { @user.update!(active: false) }
    end
    assert_equal "failed", suspension_event.status
    assert_equal 1, UserWorkers::ReconcileSuspensionWorker.jobs.size
  end

  test "reconcile still tries a node in maintenance while it is disconnected, so the action parks" do
    target = @containers.first
    target.update_columns(req_state: "running")
    (@containers - [target]).each { |c| c.update_columns(req_state: "stopped") }
    with_recorded_power_cycles(accept: ->(_c, _a) { false }) { @user.update!(active: false) }
    target.node.update_columns(disconnected: true, maintenance_requested: true)
    calls = with_recorded_power_cycles { UserWorkers::ReconcileSuspensionWorker.new.perform(@user.id, suspension_event.id, 1) }
    assert_equal [[target, "stop"]], calls.map { |c| c[0..1] }
  end

  test "the give-up note says why each container was not reached" do
    target = @containers.first
    target.update_columns(req_state: "running")
    (@containers - [target]).each { |c| c.update_columns(req_state: "stopped") }
    with_recorded_power_cycles(accept: ->(_c, _a) { false }) { @user.update!(active: false) }
    target.node.update_columns(disconnected: true)
    UserWorkers::ReconcileSuspensionWorker.new.perform(@user.id, suspension_event.id, UserWorkers::ReconcileSuspensionWorker::MAX_ATTEMPTS)
    assert_match(/#{target.name} \(node disconnected\)/, suspension_event.event_details.last.data)
  end
end
