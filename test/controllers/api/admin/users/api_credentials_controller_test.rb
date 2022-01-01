require 'test_helper'

class Api::Admin::Users::ApiCredentialsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can manage user api credentials' do

    user = users(:user)

    # Create
    data = {
      api_credential: {
        name: "Foo"
      }
    }

    post "/api/admin/users/#{user.id}/api_credentials", params: data, as: :json, headers: @basic_auth_headers

    assert_response :success

    result = JSON.parse(response.body)

    cred_id = result['api_credential']['id']
    refute cred_id.to_i.zero?

    # Delete
    delete "/api/admin/users/#{user.id}/api_credentials/#{cred_id}", params: data, as: :json, headers: @basic_auth_headers
    assert_response :success

  end

end
