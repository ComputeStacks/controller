require "test_helper"

##
# Volumes::BackupVolume#dispatch_error_code: the machine-readable reason the API answers
# 409 with. Refusals happen before any agent call, so no fake client is needed.
class Volumes::BackupVolumeDispatchCodeTest < ActiveSupport::TestCase
  setup do
    @volume = volumes(:mysql)
    @node = nodes(:testone)
  end

  test "maintenance" do
    @node.update_columns(maintenance_requested: true)
    refute @volume.create_backup!("snap")
    assert_equal "node_maintenance", @volume.dispatch_error_code
    assert_match(/in maintenance/, @volume.dispatch_error)
  end

  test "offline" do
    @node.update_columns(disconnected: true)
    refute @volume.restore_backup!("snap")
    assert_equal "node_offline", @volume.dispatch_error_code
  end

  test "no node counts as offline" do
    @volume.nodes.clear
    refute @volume.export_backup!("snap")
    assert_equal "node_offline", @volume.dispatch_error_code
    assert_equal "This volume is not assigned to a node.", @volume.dispatch_error
  end

  test "no code when nothing was refused" do
    assert_nil @volume.task_dispatch_blocker
    assert_nil @volume.dispatch_error_code
  end
end
