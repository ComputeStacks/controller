require 'test_helper'

class UserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user_skeleton = User.new(
        fname: 'John',
        lname: 'Doe',
        email: 'jdoe-test1@user.net',
        password: 'mypass!1@1x',
        password_confirmation: 'mypass!1@1x',
        country: "US",
        address1: "PO BOX 2391",
        city: "Portland",
        state: "Oregon",
        locale: "en",
        zip: "97208",
        company_name: "self"
    )
  end

  ##
  # User Validations
  test 'ensure user can be validated' do
    assert @user_skeleton.valid?
  end

  test 'require first name' do
    @user_skeleton.fname = nil
    refute @user_skeleton.valid?, 'user is valid without a first name'
    assert_not_nil @user_skeleton.errors[:fname], 'no validation error for fname present'
  end

  test 'require last name' do
    @user_skeleton.lname = nil
    refute @user_skeleton.valid?, 'user is valid without a last name'
    assert_not_nil @user_skeleton.errors[:lname], 'no validation error for lname present'
  end

  test 'invalid without email' do
    @user_skeleton.email = nil
    refute @user_skeleton.valid?, 'user is valid without an email'
    assert_not_nil @user_skeleton.errors[:email], 'no validation error for email present'
  end

  ##
  # Scopes & Class Methods
  #
  test 'ensure we can sort users' do
    assert_includes User.sorted, users(:admin)
  end

  test 'ensure we can find by_last_name' do
    assert_includes User.by_last_name, users(:admin)
  end

  # test '.with_active_subscriptions' do
  #   refute_includes User.with_active_subscriptions, users(:admin)
  # end

  test 'can view user regional pricing' do
    User.all.each do |user|
      refute_empty Region.first.user_pricing(user)
    end
  end

  ##
  # Associations

  test 'UserGroup' do
    assert_kind_of UserGroup, User.first.user_group
  end

  ##
  # User Methods
  #
  test 'ensure we can load price_list' do
    assert_kind_of Hash, User.first.price_list
  end

  # TODO: Actually test this...
  test 'ensure user has run_rate' do
    User.all.each do |u|
      assert_equal u.subscriptions.all_active.inject(0) { |sum,item| sum += item.run_rate }, u.run_rate
    end
  end

  test 'ensure user can be suspended' do
    assert User.first.suspend!
    refute User.first.active
  end

  test 'ensure user can be unsuspended' do
    assert User.first.unsuspend!
    assert User.first.active
  end

  # Update an existing user with a requested email
  test 'update with requested_email' do

    base_user = User.new(
      fname: 'John',
      lname: 'Doe',
      email: 'foo-bar-323@user.net',
      password: 'mypass!1@1x',
      password_confirmation: 'mypass!1@1x',
      country: "US",
      address1: "PO BOX 2391",
      city: "Portland",
      state: "Oregon",
      locale: "en",
      zip: "97208",
      company_name: "self"
    )

    # Create base user first
    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
      assert base_user.save
      assert_equal 'foo-bar-323@user.net', base_user.email
    end

    assert_no_enqueued_jobs do
      ##
      # Attempt to choose the same email
      base_user.requested_email = base_user.email
      assert base_user.valid?
      assert base_user.save
      assert_equal 'foo-bar-323@user.net', base_user.email

      ##
      # Choose a new available email
      base_user.requested_email = 'foo-bar-423@user.net'
      assert base_user.valid?
      assert base_user.save
      assert_equal 'foo-bar-423@user.net', base_user.email

      ##
      # Choose a new unavailable email
      base_user.requested_email = users(:admin).email
      assert base_user.valid?
      assert base_user.save
      refute_equal users(:admin).email, base_user.email

      ##
      # Finally, update normally to make sure this isn't broken!
      base_user.email = 'foo-bar-523@user.net'
      assert base_user.valid?
      assert base_user.save
      assert_equal 'foo-bar-523@user.net', base_user.email

    end

  end

  # Create a new user with a requested email
  test 'create with requested_email' do

    # Normal user first
    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
      u1 = User.new(
        fname: 'John',
        lname: 'Doe',
        email: 'jdoe-test2@user.net',
        password: 'mypass!1@1x',
        password_confirmation: 'mypass!1@1x',
        country: "US",
        address1: "PO BOX 2391",
        city: "Portland",
        state: "Oregon",
        locale: "en",
        zip: "97208",
        company_name: "self"
      )
      assert u1.save
      assert_equal 'jdoe-test2@user.net', u1.email
    end

    # requested_email always skips email validation -- this can only be done internally.
    assert_no_enqueued_jobs do
      # Try to get the same email, it should return fname.lname@
      u2 = User.new(
        fname: 'John',
        lname: 'Doe',
        requested_email: 'jdoe-test2@user.net',
        password: 'mypass!1@1x',
        password_confirmation: 'mypass!1@1x',
        country: "US",
        address1: "PO BOX 2391",
        city: "Portland",
        state: "Oregon",
        locale: "en",
        zip: "97208",
        company_name: "self"
      )

      assert u2.valid?
      assert u2.save

      assert_equal "john.doe@#{Setting.app_name.parameterize}.local", u2.email

      # Same as u2, but this time we should get a UUID email
      u3 = User.new(
        fname: 'John',
        lname: 'Doe',
        requested_email: 'jdoe-test2@user.net',
        password: 'mypass!1@1x',
        password_confirmation: 'mypass!1@1x',
        country: "US",
        address1: "PO BOX 2391",
        city: "Portland",
        state: "Oregon",
        locale: "en",
        zip: "97208",
        company_name: "self"
      )

      assert u3.valid?
      assert u3.save

      uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      assert uuid_regex.match?(u3.email.split('@').first)

      # Completely new email
      u4 = User.new(
        fname: 'John',
        lname: 'Doe',
        requested_email: 'jdoe-test3@user.net',
        password: 'mypass!1@1x',
        password_confirmation: 'mypass!1@1x',
        country: "US",
        address1: "PO BOX 2391",
        city: "Portland",
        state: "Oregon",
        locale: "en",
        zip: "97208",
        company_name: "self"
      )

      assert u4.valid?
      assert u4.save

      assert_equal 'jdoe-test3@user.net', u4.email
    end

  end

  test 'can delete user' do
    user = User.new(
      fname: 'Peter',
      lname: 'Doe',
      email: 'pdoe-test101@user.net',
      password: 'mypass!1@1x',
      password_confirmation: 'mypass!1@1x',
      country: "US",
      address1: "PO BOX 2391",
      city: "Portland",
      state: "Oregon",
      locale: "en",
      zip: "97208",
      company_name: "self"
    )
    user.skip_confirmation!
    assert user.save

    vol = Volume.new(name: SecureRandom.uuid, user: user, label: 'Peter Doe Test Volume')
    assert vol.save

    # Can't delete user with a volume!
    refute user.destroy
    assert vol.update(to_trash: true, trash_after: 1.hour.ago)
    assert vol.can_trash?
    assert vol.destroy

    user.reload

    # Delete user should work now
    # TODO: Test AppEvent Destruction works here.
    assert user.destroy
  end

end
