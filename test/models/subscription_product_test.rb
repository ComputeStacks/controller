require 'test_helper'

class SubscriptionProductTest < ActiveSupport::TestCase

  test 'can access relationships' do
    SubscriptionProduct.all.each do |sp|
      assert_kind_of BillingResource, sp.billing_resource
      assert_kind_of BillingResourcePrice, sp.price_resources.first
      assert_kind_of BillingPhase, sp.phase_resources.first

      assert_kind_of Product, sp.product

      assert_not_empty sp.prices
      assert_not_empty sp.prices
    end
  end

end
