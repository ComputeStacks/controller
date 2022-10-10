require 'test_helper'

class Api::Admin::Users::SuspensionControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can suspend and unsuspend user' do

    user = users(:suspendable_user)

    post "/api/admin/users/#{user.id}/suspension", as: :json, headers: @basic_auth_headers

    assert_response :success

    user.reload

    refute user.active

    delete "/api/admin/users/#{user.id}/suspension", as: :json, headers: @basic_auth_headers

    assert_response :success

    user.reload

    assert user.active

  end

end
