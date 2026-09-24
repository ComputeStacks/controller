require "test_helper"
require "minitest/mock"

##
# Mount detection — the other half of the `awaiting_mount` cascade.
#
# The cascade creates the Volume, its VolumeMap and the docker volume immediately with
# `awaiting_mount: true` and never rebuilds anything, so the bind only actually appears inside a
# container at that service's next natural rebuild. This service is what notices that moment,
# from inside `Containerized#build!`, using the bind list that was really sent to Docker.
#
# Two properties are load-bearing and each has a test below:
#
#   * it performs NO synchronous agent call. It runs inside
#     `Timeout.timeout(70) { container.build! event }`, and `Volume after_commit
#     :update_consul!` is a 10s HTTP PUT — so a slow agent would turn a successful build into
#     `event.fail! "Fatal error"` with the container created but never started. Hence
#     `update_columns` plus VolumeWorkers::UpdateDesiredStateWorker.
#   * it never raises. A detector bug must not be able to break container provisioning.
class VolumeServices::MarkVolumesMountedServiceTest < ActiveSupport::TestCase
  setup do
    @container = deployment_containers(:mysql_1)
    @mounted = volumes(:mysql)
    @other = volumes(:nginx_web)
    @mounted.update_columns(awaiting_mount: true)
    @other.update_columns(awaiting_mount: true)
    @event = EventLog.create!(locale: "container.provision", locale_keys: {}, status: "running",
      event_code: "test-mark-mounted")
    VolumeWorkers::UpdateDesiredStateWorker.jobs.clear
    # Nothing on this path may reach the agent. A recording double that stays empty is a
    # stronger assertion than `flunk` inside the stub, because it cannot be swallowed by the
    # service's own `rescue`.
    @agent = FakeAgentClient.new
  end

  def bind_for(volume, path = "/var/lib/mysql", mode = "rw")
    "#{volume.name}:#{path}:#{mode}"
  end

  def perform(binds, event = @event)
    Agent::Client.stub(:for_node, @agent) do
      VolumeServices::MarkVolumesMountedService.new(@container, binds, event).perform
    end
  end

  # --- the happy path -------------------------------------------------------------

  test "clears awaiting_mount only for the volumes named in the bind list" do
    assert perform([bind_for(@mounted)])

    assert_equal false, @mounted.reload.awaiting_mount
    assert_equal true, @other.reload.awaiting_mount,
      "a volume that was not in the payload Docker received must stay pending"
  end

  test "enqueues the desired-state push once per cleared volume" do
    assert perform([bind_for(@mounted), bind_for(@other, "/var/www")])

    assert_equal 2, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
    assert_equal [@mounted.id, @other.id].sort,
      VolumeWorkers::UpdateDesiredStateWorker.jobs.map { |j| j["args"].first }.sort
  end

  test "performs no synchronous agent call" do
    assert perform([bind_for(@mounted)])

    assert_empty @agent.calls,
      "clearing awaiting_mount must not put an agent HTTP call inside the container build"
  end

  test "writes one event detail naming the volumes now eligible for backups" do
    assert perform([bind_for(@mounted)])

    details = @event.event_details.where(event_code: VolumeServices::MarkVolumesMountedService::MOUNTED_EVENT_CODE)
    assert_equal 1, details.count
    assert_includes details.first.data, @mounted.name
    assert_includes details.first.data, @mounted.label
  end

  test "parses a mount path that itself contains a colon" do
    assert perform(["#{@mounted.name}:/data/a:b:rw"])

    assert_equal false, @mounted.reload.awaiting_mount
  end

  test "deduplicates repeated binds for one volume" do
    assert perform([bind_for(@mounted), bind_for(@mounted, "/var/lib/mysql", "ro")])

    assert_equal 1, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
  end

  # --- no-ops ---------------------------------------------------------------------

  test "nil binds are a no-op" do
    refute perform(nil)

    assert_equal true, @mounted.reload.awaiting_mount
    assert_equal 0, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
    assert_equal 0, @event.event_details.count
  end

  test "an empty bind list is a no-op" do
    refute perform([])

    assert_equal true, @mounted.reload.awaiting_mount
    assert_equal 0, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
  end

  test "binds naming volumes that are not awaiting mount are a no-op" do
    @mounted.update_columns(awaiting_mount: false)
    @other.update_columns(awaiting_mount: false)

    refute perform([bind_for(@mounted), bind_for(@other, "/var/www")])

    assert_equal 0, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
    assert_equal 0, @event.event_details.count
  end

  test "host path binds and junk entries are ignored" do
    refute perform(["/etc/localtime:/etc/localtime:ro", "", nil])

    assert_equal true, @mounted.reload.awaiting_mount
    assert_equal 0, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
  end

  test "a missing event is tolerated" do
    assert perform([bind_for(@mounted)], nil)

    assert_equal false, @mounted.reload.awaiting_mount
    assert_equal 1, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
  end

  # --- it can never break a build --------------------------------------------------

  test "returns false instead of raising when something goes wrong internally" do
    boom = ->(*) { raise "enqueue exploded" }

    result = VolumeWorkers::UpdateDesiredStateWorker.stub(:perform_async, boom) do
      perform([bind_for(@mounted)])
    end

    refute result, "a detector failure must be reported as false, never propagated into build!"
  end

  test "returns false instead of raising when the event detail cannot be written" do
    broken_event = Object.new # no #event_details

    refute perform([bind_for(@mounted)], broken_event)
  end

  # --- the Containerized#build! hook -----------------------------------------------

  # `Docker::Container.create` is stubbed with a real (unconnected) Docker::Container, which is
  # all `build!` inspects, and the build payload is stubbed so neither test needs a docker node.
  def fake_docker_container
    Docker::Container.send(:new, Docker::Connection.new("tcp://127.0.0.1:2376", {}), {"id" => "deadbeef"})
  end

  test "build! on a container marks the volumes in the payload it sent to docker" do
    payload = {"HostConfig" => {"Binds" => [bind_for(@mounted)]}}

    @container.stub(:runtime_config, payload) do
      Docker::Container.stub(:create, fake_docker_container) do
        Agent::Client.stub(:for_node, @agent) do
          assert @container.build!(@event)
        end
      end
    end

    assert_equal false, @mounted.reload.awaiting_mount
    assert_equal 1, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
  end

  # An SFTP build must never clear the flag: `build!` is shared with Deployment::Sftp, whose
  # build_command carries its own HostConfig.Binds, and a volume being visible over SFTP is not
  # the same thing as the customer's application being able to see it.
  test "build! on an sftp container does not touch volume state" do
    sftp = deployment_sftp(:project_test_testone)
    payload = {"HostConfig" => {"Binds" => [bind_for(@mounted)]}}

    sftp.stub(:build_command, payload) do
      Docker::Container.stub(:create, fake_docker_container) do
        Agent::Client.stub(:for_node, @agent) do
          assert sftp.build!(@event)
        end
      end
    end

    assert_equal true, @mounted.reload.awaiting_mount
    assert_equal 0, VolumeWorkers::UpdateDesiredStateWorker.jobs.size
  end
end
