require "test_helper"
require "webmock"

class Admin::RegionsControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers
  include WebMock::API

  setup do
    sign_in users(:admin)
    @region = regions(:regionone)
  end

  # These render tests exist because `f.check_box :ipv6_egress` resolves through
  # `object.public_send(:ipv6_egress)` -- no question mark, no respond_to? guard. A
  # predicate-only accessor would 500 both of these pages.
  test "new renders" do
    get "/admin/regions/new"

    assert_response :success
    assert_select "input[name='region[ipv6_egress]']"
  end

  test "edit renders" do
    get "/admin/regions/#{@region.id}/edit"

    assert_response :success
    assert_select "input[name='region[ipv6_egress]']"
  end

  test "edit renders with the flag on" do
    @region.update! ipv6_egress: true

    get "/admin/regions/#{@region.id}/edit"

    assert_response :success
    assert_select "input[name='region[ipv6_egress]'][checked='checked']"
  end

  test "update persists ipv6_egress" do
    patch "/admin/regions/#{@region.id}", params: {region: {ipv6_egress: "1"}}

    assert_redirected_to "/admin/regions/#{@region.id}"
    assert_equal true, @region.reload.ipv6_egress
  end

  test "update can turn ipv6_egress back off" do
    @region.update! ipv6_egress: true

    patch "/admin/regions/#{@region.id}", params: {region: {ipv6_egress: "0"}}

    assert_redirected_to "/admin/regions/#{@region.id}"
    assert_equal false, @region.reload.ipv6_egress
  end

  test "update does not clobber other feature keys" do
    @region.update! features: {"container_shared_storage" => true}

    patch "/admin/regions/#{@region.id}", params: {region: {ipv6_egress: "1"}}

    @region.reload
    assert_equal true, @region.features["container_shared_storage"]
    assert_equal true, @region.ipv6_egress
  end

  test "show warns that a network rebuild converts the whole zone when the flag is on" do
    @region.update! ipv6_egress: true

    get "/admin/regions/#{@region.id}"

    assert_response :success
    assert_match "convert every existing project", response.body
  end

  test "show leaves the rebuild confirmation alone when the flag is off" do
    get "/admin/regions/#{@region.id}"

    assert_response :success
    assert_no_match(/convert every existing project/, response.body)
    assert_match "This will rebuild all containers.", response.body
  end

  # The XHR branch of #show is the dashboard's metrics path and had no coverage at
  # all, which is how a `@nodes` load that no view reads survived in this action.
  test "show renders the resources partial for an xhr request" do
    WebMock.enable!
    WebMock.disable_net_connect!
    stub_request(:get, %r{/api/v1/query}).to_return(
      status: 200,
      headers: {"Content-Type" => "application/json"},
      body: {status: "success", data: {resultType: "vector", result: []}}.to_json
    )

    get "/admin/regions/#{@region.id}", xhr: true

    assert_response :success
    assert_match "CONTAINERS", response.body
    assert_no_match(/<html/, response.body) # layout: false
  ensure
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end
end
