require "test_helper"

class Admin::EventLogsControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    EventLog.create!(locale: "node.ports.open", status: "completed")
  end

  test "index renders with no filters" do
    get "/admin/event_logs"

    assert_response :success
    assert_select "select[name='kind[]'] optgroup[label='node']"
  end

  test "index renders with every filter set" do
    get "/admin/event_logs", params: {
      status: "failed", kind: ["node.*", "made.up"], period: "7d", timerange: "2026-10-01 - 2026-10-15",
      performed_by: "system", code: "abc", with_details: "1", with_system_events: "1"
    }

    assert_response :success
    assert_select "option[value='made.up'][selected]"
    assert_select "option[value='node.*'][selected]"
  end

  test "filters are applied to the list" do
    get "/admin/event_logs", params: {code: "no-such-code"}

    assert_response :success
    assert_select "td", text: "No events"
  end

  test "performed by shows the chosen user's label" do
    user = users(:admin)
    get "/admin/event_logs", params: {performed_by: user.id}

    assert_response :success
    assert_select "input[name='performed_by'][value='#{user.id}']"
    assert_select "input[type='text'][value=?]", user.full_name_with_email
  end

  test "user autocomplete matches partial name or email, and ids" do
    user = users(:admin)

    get "/admin/users/autocomplete", params: {q: user.email[0, 4].upcase}
    assert_response :success
    assert_includes response.parsed_body.map { |u| u["id"] }, user.id

    get "/admin/users/autocomplete", params: {q: user.id.to_s}
    assert_includes response.parsed_body.map { |u| u["id"] }, user.id

    get "/admin/users/autocomplete", params: {q: "a"}
    assert_equal [], response.parsed_body

    get "/admin/users/autocomplete", params: {q: "%_"}
    assert_equal [], response.parsed_body
  end

  test "invalid range warns but still renders" do
    get "/admin/event_logs", params: {timerange: "nope"}

    assert_response :success
    assert_match "Invalid date range", response.body
  end

  test "user event log page renders with filters" do
    user = users(:admin)
    get "/admin/users/#{user.id}/event_logs", params: {kind: ["node.*"]}

    assert_response :success
  end
end
