require "test_helper"

##
# See Volumes::AwaitingMountGuardsTest -- same refusal, API shape.
class Api::Volumes::AwaitingMountGuardsTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @volume = volumes(:mysql)
    # update_columns: avoid the after_commit that pushes desired state to the agent.
    @volume.update_columns(awaiting_mount: true)
  end

  test "backup is refused while awaiting mount" do
    post "/api/volumes/#{@volume.id}/backups",
      params: {name: "manual-backup"}.to_json,
      headers: @basic_auth_headers

    assert_response :method_not_allowed
    assert_match(/not mounted by any container yet/, JSON.parse(response.body)["errors"].first)
  end

  test "restore is refused while awaiting mount" do
    post "/api/volumes/#{@volume.id}/restore",
      params: {name: "some-archive"}.to_json,
      headers: @basic_auth_headers

    assert_response :method_not_allowed
    assert_match(/not mounted by any container yet/, JSON.parse(response.body)["errors"].first)
  end
end
