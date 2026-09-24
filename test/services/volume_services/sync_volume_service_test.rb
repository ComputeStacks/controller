require "test_helper"
require "minitest/mock"

##
# SyncVolumeService imports volumes it finds on a node that the controller does not know about
# — typically an anonymous docker volume created because the image declares a `VOLUME` that
# ComputeStacks never did (scratch paths like /tmp or /run). Backups are deliberately left off
# for those.
#
# The invariant that was broken: the owner VolumeMap sat inside the `unless save` FAILURE branch,
# so every SUCCESSFUL import produced a service-less volume, which `set_detached` then stamped —
# minting a standalone "Detached Volume" subscription that accrued a usage row every collection
# cycle forever (19 volumes are in that state on production). The failure branch itself was close
# to unreachable, and all it could do there was raise.
#
# Two classifications matter as much as the map, and are pinned below:
#   * a volume that cannot be represented as a mount (the service already maps that path — which
#     is exactly what the image volume cascade leaves behind until a rebuild) is a SKIP, and the
#     run still completes. Failing it would mark this nightly job failed indefinitely.
#   * a genuine fault fails the run, but only after the whole fleet has been swept.
class VolumeServices::SyncVolumeServiceTest < ActiveSupport::TestCase
  # Stands in for Docker::Volume.
  class FakeDockerVolume
    def initialize(name, labels = nil)
      @info = {"Name" => name}
      @info["Labels"] = labels if labels
    end

    attr_reader :info
  end

  # Stands in for DockerVolumeLocal::Node.
  class FakeVolumeNode
    def initialize(volumes)
      @volumes = volumes
    end

    def list_all_volumes = @volumes
  end

  setup do
    @node = nodes(:testone)
    @service = deployment_container_services(:wordpress)
    @container = deployment_containers(:wordpress_1)
    @event = EventLog.create!(
      locale: "system.sync_volumes",
      event_code: "f99c17d69be552bc",
      status: "running"
    )
  end

  # Runs perform with the node sweep, the docker volume listing and the agent transport stubbed.
  #
  # @param found [Array<FakeDockerVolume>] what the node reports
  # @param inspections [Hash{String => Array<Hash>}] volume name => inspect_volume_by_name result
  def sync(found:, inspections:)
    Node.stub(:online, [@node]) do
      DockerVolumeLocal::Node.stub(:new, FakeVolumeNode.new(found)) do
        Volume.stub(:inspect_volume_by_name, ->(name) { inspections.fetch(name, []) }) do
          Agent::Client.stub(:for_node, FakeAgentClient.new) do
            VolumeServices::SyncVolumeService.new(@event).perform
          end
        end
      end
    end
  end

  def mount(path, container = @container)
    [{container_name: container.name, node_id: @node.id, volume_driver: "local", mount_path: path}]
  end

  test "an imported volume gets its owner map, so it is never service-less or detached" do
    name = SecureRandom.hex(32) # docker's anonymous volume shape

    assert sync(found: [FakeDockerVolume.new(name)], inspections: {name => mount("/tmp")})

    volume = Volume.find_by(name: name)
    assert volume, "the volume was imported"
    map = volume.volume_maps.sole

    assert_equal @service, map.container_service
    assert_equal "/tmp", map.mount_path
    assert map.is_owner, "without is_owner, Volume#container_service stays nil"
    assert_equal @service, volume.container_service
    refute volume.borg_enabled, "an anonymous scratch volume is deliberately not backed up"
    assert_equal [@node], volume.nodes.to_a,
      "runtime_config's bind filter and update_consul!'s node choice both read volume.nodes"

    # The whole point of committing the map in the same transaction as the volume.
    assert_nil volume.detached_at,
      "a detached_at stamp mints a 'Detached Volume' subscription and bills it forever"
    assert_nil volume.subscription_id
    assert @event.reload.success?
  end

  test "a path the service already maps is a skip, not a failure, with no orphan volume" do
    # This is the image-volume-cascade shape: the cascade attaches a volume at /var/www and
    # rebuilds nothing, so docker's anonymous volume is still mounted there tonight. Failing the
    # run for it would mean a failed event every night until that service is next rebuilt.
    name = SecureRandom.hex(32)

    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      assert sync(found: [FakeDockerVolume.new(name)], inspections: {name => mount("/var/www")})
    end

    details = @event.event_details.map(&:data).join("\n")
    assert_match(/cannot be represented as a mount/, details)
    assert_match(/already exists|already in use/, details)
    assert @event.reload.success?, "a stable, unrepresentable volume must not fail the nightly run"
  end

  test "a path nested under an existing mount is a skip too" do
    # wordpress already maps /var/www; VolumeMap#no_nested_volumes rejects anything beneath it.
    name = SecureRandom.hex(32)

    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      assert sync(found: [FakeDockerVolume.new(name)], inspections: {name => mount("/var/www/html")})
    end

    assert_match(/cannot be represented as a mount/, @event.event_details.map(&:data).join("\n"))
    assert @event.reload.success?
  end

  test "a mount path docker and ComputeStacks would spell differently is refused" do
    # safe_mount (Zaru) would store this as /var/my_data, so the bind at the next rebuild would
    # land where the app never writes. Refuse rather than map a path that corresponds to nothing.
    name = SecureRandom.hex(32)

    assert_no_difference "Volume.count" do
      assert sync(found: [FakeDockerVolume.new(name)], inspections: {name => mount("/var/my data")})
    end

    assert_match(/would be stored as/, @event.event_details.map(&:data).join("\n"))
  end

  test "an unimportable volume does not stop the rest of the sweep" do
    bad = SecureRandom.hex(32)
    good = SecureRandom.hex(32)

    assert sync(
      found: [FakeDockerVolume.new(bad), FakeDockerVolume.new(good)],
      inspections: {bad => mount("/var/www/html"), good => mount("/tmp")}
    )

    assert_nil Volume.find_by(name: bad)
    imported = Volume.find_by(name: good)
    assert imported, "a volume queued after a skipped one is still imported"
    assert_equal "/tmp", imported.volume_maps.sole.mount_path
  end

  test "an exception on one volume neither aborts the sweep nor leaves the event running" do
    # The structural guarantee. Anything that escapes import_volume used to unwind into
    # SyncLocalVolumeWorker's catch-all, which alerts but never closes the EventLog: the run sat
    # at "running" forever and every later volume — and every later node — went unprocessed.
    boom = SecureRandom.hex(32)
    good = SecureRandom.hex(32)
    inspections = {boom => mount("/tmp"), good => mount("/run")}

    result = Node.stub(:online, [@node]) do
      DockerVolumeLocal::Node.stub(:new, FakeVolumeNode.new([FakeDockerVolume.new(boom), FakeDockerVolume.new(good)])) do
        Volume.stub(:inspect_volume_by_name, ->(name) {
          raise Excon::Error::Timeout, "node fell over" if name == boom
          inspections.fetch(name, [])
        }) do
          Agent::Client.stub(:for_node, FakeAgentClient.new) do
            VolumeServices::SyncVolumeService.new(@event).perform
          end
        end
      end
    end

    refute result, "a genuine fault fails the run"
    assert @event.reload.failed?, "and closes the event rather than leaving it running"
    assert_match(/Excon::Error::Timeout/, @event.event_details.map(&:data).join("\n"))
    assert Volume.find_by(name: good), "the volume after the exception is still imported"
  end

  test "a volume mounted by no known container is skipped, not imported" do
    name = SecureRandom.hex(32)

    assert_no_difference "Volume.count" do
      assert sync(found: [FakeDockerVolume.new(name)], inspections: {name => []})
    end

    assert_match(/skipped due to missing local service/, @event.event_details.map(&:data).join("\n"))
    assert @event.reload.success?
  end

  test "a volume already known to the controller only gains the node" do
    existing = volumes(:mysql)
    existing.nodes.destroy_all

    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      assert sync(found: [FakeDockerVolume.new(existing.name)], inspections: {})
    end

    assert_includes existing.reload.nodes, @node
  end

  test "system and backup role volumes are ignored" do
    assert_no_difference "Volume.count" do
      assert sync(
        found: [
          FakeDockerVolume.new(SecureRandom.hex(32), {"com.computestacks.role" => "backup"}),
          FakeDockerVolume.new(SecureRandom.hex(32), {"com.computestacks.role" => "system"})
        ],
        inspections: {}
      )
    end
  end
end
