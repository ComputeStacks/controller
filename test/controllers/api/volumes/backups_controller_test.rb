require "test_helper"
require "minitest/mock"

class Api::Volumes::BackupsControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @volume = volumes(:mysql)
    @fake = FakeAgentClient.new
  end

  # Archive ids are urlsafe base64; this name encodes with a `-`.
  test "delete decodes a urlsafe archive id" do
    name = "café~-m-2026-10-09T01:02:03"
    id = Base64.urlsafe_encode64(name)
    assert_match(/[-_]/, id)

    Agent::Client.stub(:for_node, @fake) do
      delete "/api/volumes/#{@volume.id}/backups/#{id}", headers: @basic_auth_headers
    end

    assert_response :ok
    assert_equal name, @fake.last_call(:create_task)[1][:archive]
  end

  test "delete rejects an id that is not urlsafe base64" do
    Agent::Client.stub(:for_node, @fake) do
      delete "/api/volumes/#{@volume.id}/backups/!!!!", headers: @basic_auth_headers
    end

    assert_response :unprocessable_entity
    assert_empty @fake.calls_of(:create_task)
  end
end
