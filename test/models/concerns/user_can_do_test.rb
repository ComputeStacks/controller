require 'test_helper'

class UserCanDoTest < ActiveSupport::TestCase

  setup do
    @user = User.first
  end

  test 'has_quota' do
    assert @user.current_quota.is_a?(Hash)
  end

  test 'can_order_container' do
    assert @user.can_order_containers?
  end

  test 'can_order_registry' do
    assert @user.can_order_cr?
  end

end