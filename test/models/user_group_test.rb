require 'test_helper'

class UserGroupTest < ActiveSupport::TestCase

  setup do
    @bp = BillingPlan.first
    @bp = BillingPlan.create!(name: 'test') if @bp.nil?
  end

  test 'create user group' do
    assert UserGroup.create!(name: 'test_group', billing_plan: @bp)
  end

  test "can't create group without a name" do
    ug = UserGroup.new(billing_plan: @bp)
    refute ug.valid?, 'user group is valid without a name'
    assert_not_nil ug.errors[:name], 'no validation error for name present'
  end

  test "can't create group without a billing plan" do
    ug = UserGroup.new name: 'test'
    refute ug.valid?, 'user group is valid without a billing group'
    assert_not_nil ug.errors[:billing_plan], 'no validation error for billing plan present'
  end

end