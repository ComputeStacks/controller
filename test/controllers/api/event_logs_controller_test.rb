require 'test_helper'

class Api::EventLogsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can view event log' do
    container = Deployment::Container.first
    audit = Audit.create_from_object!(container, 'testevent', '127.0.0.1', users(:admin))
    event = EventLog.create!(
      locale_keys: {
        label: container.label,
        container: container.name
      },
      locale: 'container.start',
      status: "pending",
      event_code: 'foobar1111',
      audit: audit
    )

    event.event_details.create!( data: "foobar", event_code: "barfoo" )

    get "/api/event_logs/#{event.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal event.event_code, data['event_log']['event_code']
    assert_equal event.event_details.first.event_code, data['event_log']['event_details'][0]['event_code']

  end
end
