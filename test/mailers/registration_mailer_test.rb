require 'test_helper'

class RegistrationMailerTest < ActionMailer::TestCase

  setup do
    I18n.locale = 'en'
    @user = User.first
    @token = SecureRandom.hex(8)
  end
  # TODO: Create settings fixture and set a localhost mailer? not sure.
  test "confirmation" do
    email = RegistrationMailer.confirmation_instructions @user, @token

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to

  end

  test "password_reset" do
    email = RegistrationMailer.reset_password_instructions @user, @token

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to

  end

  test "unlock" do
    email = RegistrationMailer.unlock_instructions @user, @token

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to

  end

end
