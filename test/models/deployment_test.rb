require 'test_helper'

class DeploymentTest < ActiveSupport::TestCase

  test 'can change deployment owner' do
    admin = User.find_by(email: 'peter@pp.net')
    user = User.find_by(email: 'a@example.local')

    d = Deployment.first

    orig_user = d.user
    new_user = orig_user == admin ? user : admin

    d.user = new_user

    audit = Audit.create_from_object!(d, 'updated', '127.0.0.1', admin)

    d.current_audit = audit

    successful_save = d.save

    assert_empty d.errors.full_messages

    assert successful_save # Check after to capture errors for easier debugging

    assert_equal d.user, new_user

    d.domains.each do |domain|
      assert_equal domain.user, new_user
    end

    d.volumes.each do |vol|
      assert_equal vol.user, new_user
    end

    d.subscriptions.each do |sub|
      assert_equal sub.user, new_user
    end
  end

  test 'can list deployments' do

    d = Deployment.first
    u = d.user

    assert_includes Deployment.find_all_for(u), d
  end

end
