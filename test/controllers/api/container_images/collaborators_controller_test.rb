require 'test_helper'

class Api::ContainerImages::CollaboratorsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  def before_setup
    super
    @item = container_images :custom
    user = users(:user)
    @collab = @item.container_image_collaborators.new collaborator: user, skip_confirmation: true, current_user: users(:admin)
    @collab.save
    @collab_base_path = "/api/container_images/#{@item.id}/collaborators"
  end

  def before_teardown
    @item.container_image_collaborators.delete_all
    super
  end

  test "list image collaborations" do

    get @collab_base_path, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data['collaborators']

    data['collaborators'].each do |i|
      refute_nil i['id']
      user = i['collaborator']
      refute_nil user['id']
      refute_nil user['email']
      refute_nil user['full_name']

      u = User.find user['id']
      assert_equal u.email, user['email']
      assert_equal u.full_name, user['full_name']
    end

  end

  test 'can view collaborator' do
    get "#{@collab_base_path}/#{@collab.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data['collaboration']

    assert_equal "#{@collab.id}-image", data['collaboration']['id']
    assert_equal @item.id, data['collaboration']['image']['id']
    assert_equal @item.label, data['collaboration']['image']['name']
    assert_equal @item.user.id, data['resource_owner']['id']
    assert_equal @item.user.email, data['resource_owner']['email']
    assert_equal @item.user.full_name, data['resource_owner']['full_name']

  end

end
