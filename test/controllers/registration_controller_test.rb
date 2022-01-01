require 'test_helper'

class RegistrationControllerTest < ActionDispatch::IntegrationTest

  include ActiveJob::TestHelper
  # include ActionMailer::TestHelper

  test "register" do
    Setting.find_by(name: 'signup_form').update_column(:value, true) unless Setting.enable_signup_form?
    Setting.find_by(name: 'smtp_from').update_column(:value, "foobar@cstacks.local") unless Setting.smtp_configured?
    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
    # assert_emails 1 do
      post "/register", params: {
          user: {
              fname: "John",
              lname: "Doe",
              email: "jdoe-controller@example.net",
              password: "mypass!1@1x",
              password_confirmation: "mypass!1@1x",
              country: "US",
              address1: "PO BOX 2391",
              address2: "c/o John Doe",
              city: "Portland",
              state: "Oregon",
              locale: "en",
              zip: "97208",
              company_name: "self",
              is_admin: true # Should not be allowed here!
          }
      }
    end

    user = User.find_by(email: 'jdoe-controller@example.net')
    assert_not_nil user

    assert_equal user.address1, "PO BOX 2391"
    assert_equal user.address2, "c/o John Doe"
    assert_equal user.fname, "John"
    assert_equal user.lname, "Doe"
    assert_equal user.country, "US"
    assert_equal user.city, "Portland"
    assert_equal user.state, "Oregon"
    assert_equal user.locale, "en"
    assert_equal user.currency, ENV['CURRENCY']
    assert_equal user.company_name, "self"
    assert_equal user.zip, "97208"
    assert_equal user.is_admin, false

    assert user.valid_password?("mypass!1@1x")



  end

end
