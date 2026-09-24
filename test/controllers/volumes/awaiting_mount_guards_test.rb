require "test_helper"

##
# A volume that is awaiting its first mount exists on the node, but no container carries the
# bind yet. Manual backup would write a healthy-looking empty archive, and a restore would
# report success while the application never sees the data -- both are refused.
class Volumes::AwaitingMountGuardsTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    @volume = volumes(:mysql)
    # update_columns: avoid the after_commit that pushes desired state to the agent.
    @volume.update_columns(awaiting_mount: true)
    @archive = Base64.urlsafe_encode64("some-archive")
  end

  test "backup is refused while awaiting mount" do
    sign_in users(:admin)

    post "/volumes/#{@volume.id}/backups", params: {name: "manual-backup"}

    assert_response :redirect
    assert_match(/not mounted by any container yet/, flash[:alert])
  end

  test "restore is refused while awaiting mount" do
    sign_in users(:admin)

    put "/volumes/#{@volume.id}/restore/#{@archive}"

    assert_response :redirect
    assert_match(/not mounted by any container yet/, flash[:alert])
  end

  test "admin backup is refused while awaiting mount" do
    sign_in users(:admin)

    post "/admin/volumes/#{@volume.id}/backups", params: {name: "manual-backup"}

    assert_response :redirect
    assert_match(/not mounted by any container yet/, flash[:alert])
  end

  test "admin restore is refused while awaiting mount" do
    sign_in users(:admin)

    put "/admin/volumes/#{@volume.id}/restore/#{@archive}"

    assert_response :redirect
    assert_match(/not mounted by any container yet/, flash[:alert])
  end
end
