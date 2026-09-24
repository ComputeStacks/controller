require "test_helper"
require "minitest/mock"

##
# NodeWorkers::HeartbeatWorker's capacity refresh.
#
# The refresh is a best-effort fact update bolted onto the heartbeat, and everything
# below exists to prove it stays that way: GET /info enumerates images and containers
# and is materially heavier than the GET /_ping that decides online vs offline, so it
# must never be able to mark a node offline, hold up a node coming back online, or
# overwrite a good reading with a zero.
class NodeWorkers::HeartbeatWorkerTest < ActiveSupport::TestCase
  INFO = {"NCPU" => 48, "MemTotal" => 8 * 1024 * 1024 * 1024}.freeze # 48 cores / 8192 MB

  setup do
    @node = nodes(:testone)
    @node.update!(job_status: "idle")
  end

  test "records cpu, memory and a timestamp from a successful Docker.info" do
    freeze_time do
      up { NodeWorkers::HeartbeatWorker.new.perform(@node.global_id) }

      @node.reload
      assert_equal 48, @node.cpu_cores
      assert_equal 8192, @node.memory_mb
      assert_equal Time.current, @node.capacity_updated_at
    end
  end

  test "leaves the previous reading alone when Docker.info raises" do
    seed_capacity
    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    assert_unchanged_capacity
  end

  test "leaves the previous reading alone when Docker.info reports zeros" do
    seed_capacity
    up(info: {"NCPU" => 0, "MemTotal" => 0}) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    assert_unchanged_capacity
  end

  test "leaves the previous reading alone when Docker.info answers nothing at all" do
    seed_capacity
    up(info: {}) { NodeWorkers::HeartbeatWorker.new.perform(@node.global_id) }

    assert_unchanged_capacity
  end

  ##
  # The one that matters. A failing /info must not be able to strand a node in the
  # disconnected state -- that is the difference between a slow metrics call and an
  # outage that keeps a recovered node out of the fleet.
  test "a failing refresh does not disturb the offline to online transition" do
    @node.update!(disconnected: true, failed_health_checks: 3)

    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    @node.reload
    refute @node.disconnected, "the node must come back online regardless of /info"
    assert_equal 0, @node.failed_health_checks
    assert_not_nil @node.online_at
    assert_nil @node.cpu_cores
  end

  test "a failing refresh does not disturb the failed_health_checks reset" do
    @node.update!(disconnected: false, failed_health_checks: 1, online_at: Time.now)

    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    assert_equal 0, @node.reload.failed_health_checks
  end

  test "a failing refresh does not mark a healthy node offline" do
    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    @node.reload
    refute @node.disconnected
    assert_equal 0, @node.failed_health_checks
  end

  test "an offline node is not asked for its capacity" do
    called = false
    down(info: ->(*) { called = true; INFO }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    refute called, "a Docker.info timeout on every unreachable node, every minute, is the " \
      "cost this guard exists to avoid"
    assert_equal 1, @node.reload.failed_health_checks
  end

  test "the refresh mutates a COPY of the connection options, not the shared hash" do
    before = Docker.connection.options.dup
    up { NodeWorkers::HeartbeatWorker.new.perform(@node.global_id) }

    # Docker.connection is memoised process-wide and Docker::Connection holds its
    # options hash by reference, so anything that mutates it in place is writing to
    # every other Sidekiq thread's timeouts at the same time.
    #
    # Every site that builds a Docker::Connection now dups this hash, so a whole perform
    # must leave it byte-identical.
    #
    # An earlier version of this test asserted specific timeout values instead. That was
    # order-dependent: Docker.connection.options is memoised for the life of the process,
    # so any other test that mutates it in place -- and RegionMigratorService#infra_online?
    # did, until this branch -- could make these assertions pass or fail with no relation
    # to the code under test. Comparing against a snapshot taken in this test is the only
    # form that stays honest in a single-process suite.
    assert_equal before, Docker.connection.options
  end

  private

  # Node reachable: ping answers OK, so the worker treats it as online.
  def up(info: INFO, &block)
    Docker.stub(:ping, "OK") { Docker.stub(:info, info, &block) }
  end

  # Node unreachable: ping answers anything but OK.
  def down(info: INFO, &block)
    Docker.stub(:ping, "nope") { Docker.stub(:info, info, &block) }
  end

  def seed_capacity
    @node.update_columns(cpu_cores: 16, memory_mb: 32_768, capacity_updated_at: 2.days.ago)
    @seeded_at = @node.reload.capacity_updated_at
  end

  def assert_unchanged_capacity
    @node.reload
    assert_equal 16, @node.cpu_cores
    assert_equal 32_768, @node.memory_mb
    assert_equal @seeded_at.to_i, @node.capacity_updated_at.to_i
  end
end
