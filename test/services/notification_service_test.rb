require 'test_helper'

class NotificationServiceTest < ActionMailer::TestCase

  test 'an alert can trigger a notification' do

    alert = alert_notifications(:alert_one)
    Sidekiq::Testing.inline! do
      assert_emails 2 do
        ProcessAlertWorker.perform_async alert.id
      end
    end

  end

  test 'an app event can trigger a notification' do

    u = users(:user)

    Sidekiq::Testing.inline! do
      assert_emails 1 do
        ProcessAppEventWorker.perform_async 'UserActivated', nil, u.global_id
      end
    end

  end

end
