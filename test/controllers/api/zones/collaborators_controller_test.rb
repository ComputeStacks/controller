require 'test_helper'

class Api::Zones::CollaboratorsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  ##
  # TODO: Currently fails because we need a dummy provision driver for DNS Zones
  #
  # test "list dns zone collaborations" do
  #
  #   item = dns_zones :user_zone
  #
  #   user = users(:user)
  #   c = item.dns_zone_collaborators.new collaborator: user, skip_confirmation: true, current_user: users(:admin)
  #   assert c.save
  #
  #   get "/api/zones/#{item.id}/collaborators", as: :json, headers: @basic_auth_headers
  #
  #   puts response.body
  #
  #   assert_response :success
  #
  #   data = JSON.parse(response.body)
  #   # {"collaborators"=>[{"id"=>23, "resource_owner"=>{"id"=>135138680, "email"=>"peter@pp.net", "full_name"=>"Peter Pettigrew"}}]}
  #
  #   refute_empty data['collaborators']
  #
  #   data['collaborators'].each do |i|
  #     refute_nil i['id']
  #     owner = i['resource_owner']
  #     refute_nil owner['id']
  #     refute_nil owner['email']
  #     refute_nil owner['full_name']
  #
  #     u = User.find owner['id']
  #     assert_equal u.email, owner['email']
  #     assert_equal u.full_name, owner['full_name']
  #   end
  #
  #   item.dns_zone_collaborators.delete_all
  #
  # end

end
