require "test_helper"

# The admin landing page had no test at all. Both of its paths are covered here
# because the regions panel now reads a preloaded `@locations` set by the
# controller instead of querying `Location.active` from the view -- an ivar set in
# the wrong branch would 500 the page every admin sees first.
class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
  end

  test "index renders" do
    get "/admin/dashboard"

    assert_response :success
  end

  test "index renders a row for each region that has nodes" do
    region = regions(:regionone)
    assert_predicate region.nodes, :any?, "fixture region must have a node for this to prove anything"

    get "/admin/dashboard"

    assert_response :success
    # The row the metrics XHR later fills in -- proves the preloaded @locations
    # path selects the same regions the old joins(:nodes).distinct did.
    assert_select "tr.remote-resource[data-url=?]", "/admin/regions/#{region.id}"
  end

  test "index leaves out a region with no nodes" do
    empty = Region.create!(location: locations(:testlocation), name: "nodeless",
      p_net_size: 28, network_driver: "bridge")

    get "/admin/dashboard"

    assert_response :success
    assert_select "tr.remote-resource[data-url=?]", "/admin/regions/#{empty.id}",
      count: 0
  end

  test "index orders locations and their regions by name" do
    location = locations(:testlocation)
    # Names chosen so alphabetical order is the reverse of creation order -- an
    # unordered query would very likely return them the other way round.
    %w[zulu alpha mike].each do |name|
      region = Region.create!(location: location, name: name, p_net_size: 28, network_driver: "bridge")
      Node.create!(label: "n-#{name}", hostname: "n-#{name}", primary_ip: "127.0.0.1",
        public_ip: "127.0.0.1", region: region, active: true)
    end

    get "/admin/dashboard"

    assert_response :success
    rendered = css_select("tr.remote-resource").map { |el| el["data-url"] }
    ids = rendered.map { |url| url[%r{/admin/regions/(\d+)}, 1].to_i }
    names = Region.where(id: ids).index_by(&:id).values_at(*ids).map(&:name)

    assert_equal names.sort_by(&:downcase), names,
      "region rows must be ordered by name, got #{names.inspect}"
  end

  test "index renders the recent users panel" do
    get "/admin/dashboard"

    assert_response :success
    assert_match "RECENT USERS", response.body
    assert_match users(:admin).full_name, response.body
  end

  # /admin/changelog serves the HTML that `rake generate_changelog` builds from
  # CHANGELOG.md. Pinned because the view wraps it in `.changelog`, which is where
  # all of the release-note formatting now lives.
  test "changelog renders the generated html inside the styled wrapper" do
    path = Rails.root.join("CHANGELOG.html")
    existed = path.exist?
    original = existed ? path.read : nil
    path.write("<h2>v9.9.9</h2>\n<ul><li>a change entry</li></ul>\n")

    get "/admin/changelog"

    assert_response :success
    assert_select ".changelog h2", text: "v9.9.9"
    assert_select ".changelog ul li", text: "a change entry"
  ensure
    existed ? path.write(original) : path.delete
  end

  test "the xhr path renders the health fragment without a layout" do
    get "/admin/dashboard", xhr: true

    assert_response :success
    assert_no_match(/<html/, response.body)
  end
end
