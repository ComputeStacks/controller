require "test_helper"
require "minitest/mock"

##
# `volumes.awaiting_mount` — the row, its VolumeMap and the docker volume all exist, but no
# container has been created with the bind yet (binds are baked at container-create time, and
# the cascade deliberately never rebuilds anything).
#
# These are the three READ sites that have to honour the flag. The one that matters most is
# `default_consul_data[:backup]`: every desired-state push to the agent funnels through that
# hash, so if it leaks `true` the agent starts scheduling borg backups of an empty volume and
# builds a healthy-looking archive series containing none of the customer's data.
class VolumeAwaitingMountTest < ActiveSupport::TestCase
  # Stands in for DockerVolumeLocal::Node — Containers::SshVolumes#volumes intersects the DB
  # scope with the volumes docker actually reports on the node.
  class FakeVolumeNode
    FakeVolume = Struct.new(:id)

    def initialize(names)
      @names = names
    end

    def list_all_volumes
      @names.map { |n| FakeVolume.new(n) }
    end
  end

  setup do
    @volume = volumes(:mysql)
  end

  # --- column default -------------------------------------------------------------

  test "a newly created volume is not awaiting mount" do
    volume = Volume.create!(label: "fresh", region: regions(:regionone), user: users(:admin))
    assert_equal false, volume.awaiting_mount
    assert_equal false, volume.reload.awaiting_mount
  end

  test "the awaiting_mount scope selects only flagged volumes" do
    @volume.update_columns(awaiting_mount: true)
    assert_includes Volume.awaiting_mount, @volume
    refute_includes Volume.awaiting_mount, volumes(:nginx_web)
  end

  # --- agent desired state --------------------------------------------------------

  test "default_consul_data suppresses backup while awaiting mount even when borg_enabled" do
    @volume.update_columns(borg_enabled: true, awaiting_mount: true)
    assert_equal false, @volume.send(:default_consul_data)[:backup],
      "the agent must never be told to back up a volume no container has mounted"
  end

  test "default_consul_data enables backup once the volume is mounted" do
    @volume.update_columns(borg_enabled: true, awaiting_mount: false)
    assert_equal true, @volume.send(:default_consul_data)[:backup]
  end

  test "default_consul_data leaves backup off when borg is disabled" do
    @volume.update_columns(borg_enabled: false, awaiting_mount: false)
    assert_equal false, @volume.send(:default_consul_data)[:backup]
  end

  test "the suppression survives the desired-state PUT, not just the local hash" do
    @volume.update_columns(borg_enabled: true, awaiting_mount: true)
    fake = FakeAgentClient.new
    Agent::Client.stub(:for_node, fake) { assert @volume.update_consul! }
    _, _project_id, _name, desired = fake.calls_of(:put_volume).first
    assert_equal false, desired[:backup]
  end

  # --- SFTP exposure --------------------------------------------------------------

  test "SshVolumes#volumes excludes an awaiting-mount volume" do
    sftp = deployment_sftp(:project_test_testone)
    sftp_vol = volumes(:wordpress_web)
    other_vol = volumes(:nginx_web)
    fake_node = FakeVolumeNode.new([sftp_vol.name, other_vol.name])

    DockerVolumeLocal::Node.stub(:new, fake_node) do
      names = sftp.volumes.map { |v| v["volume"] }
      assert_includes names, sftp_vol.name, "baseline: an sftp-enabled mounted volume is exposed"
      assert_includes names, other_vol.name

      sftp_vol.update_columns(awaiting_mount: true)

      names = sftp.volumes.map { |v| v["volume"] }
      refute_includes names, sftp_vol.name,
        "an awaiting-mount volume must not be mounted into the SFTP container"
      assert_includes names, other_vol.name
    end
  end

  # --- the bind MUST still be emitted ----------------------------------------------

  # The one place an `awaiting_mount: false` filter must NEVER be added, and the reason is
  # circular: emitting the bind is the only thing that lets the flag clear. If a future change
  # copied the filter from Containers::SshVolumes#volumes into runtime_config "for consistency",
  # the bind would never reach Docker, MarkVolumesMountedService would never see the volume
  # name, and every cascaded volume would stay empty with its backups suppressed forever —
  # while the whole suite stayed green. So pin it here.
  test "runtime_config still emits the bind for an awaiting-mount volume" do
    container = deployment_containers(:mysql_1)
    volume = volumes(:mysql)
    bind_for = ->(c) {
      Array(c.runtime_config(nil).dig("HostConfig", "Binds")).find { |b| b.start_with?("#{volume.name}:") }
    }

    assert bind_for.call(container), "baseline: a mounted volume is bound into the container"

    volume.update_columns(awaiting_mount: true)
    container.reload

    assert bind_for.call(container),
      "an awaiting-mount volume MUST still be bound — that bind is what clears the flag"
  end

  # --- clone sources --------------------------------------------------------------

  test "available_to_clone excludes an awaiting-mount volume" do
    param = container_image_volume_params(:mysql_data)
    param.current_user = users(:admin)
    @volume.update_columns(template_id: param.id)

    assert_includes param.available_to_clone, @volume, "baseline: a mounted volume is clonable"

    @volume.update_columns(awaiting_mount: true)
    refute_includes param.available_to_clone, @volume
  end
end
