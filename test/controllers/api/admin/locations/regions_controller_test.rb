require "test_helper"

class Api::Admin::Locations::RegionsControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @location = locations(:testlocation)
    @region = regions(:regionone)
  end

  test "can list all" do
    get "/api/admin/locations/#{@location.id}/regions", as: :json, headers: @basic_auth_headers

    assert_response :success
    # data = JSON.parse(response.body)
    # assert_not_empty data['user_groups']
  end

  # The rabl reads `ipv6_egress` off the model directly -- a predicate-only accessor
  # would blow the whole template up.
  test "index includes ipv6_egress" do
    get "/api/admin/locations/#{@location.id}/regions", as: :json, headers: @basic_auth_headers

    assert_response :success
    region = JSON.parse(response.body)["regions"].find { |r| r["id"] == @region.id }
    assert_not_nil region
    assert_equal false, region["ipv6_egress"]
  end

  test "show includes ipv6_egress" do
    @region.update! ipv6_egress: true

    get "/api/admin/locations/#{@location.id}/regions/#{@region.id}", as: :json, headers: @basic_auth_headers

    assert_response :success
    assert_equal true, JSON.parse(response.body)["region"]["ipv6_egress"]
  end

  test "update can set ipv6_egress" do
    patch "/api/admin/locations/#{@location.id}/regions/#{@region.id}",
      params: {region: {ipv6_egress: true}}.to_json,
      headers: @basic_auth_headers

    assert_response :success
    assert_equal true, @region.reload.ipv6_egress
    assert_equal true, JSON.parse(response.body)["region"]["ipv6_egress"]
  end

  test "update can unset ipv6_egress" do
    @region.update! ipv6_egress: true

    patch "/api/admin/locations/#{@location.id}/regions/#{@region.id}",
      params: {region: {ipv6_egress: false}}.to_json,
      headers: @basic_auth_headers

    assert_response :success
    assert_equal false, @region.reload.ipv6_egress
  end
end
