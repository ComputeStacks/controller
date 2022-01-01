require 'test_helper'

class SubscriptionTest < ActiveSupport::TestCase

  # TODO: Load up some dummy storage/bw/backup data to test that.
  test 'correct run rate' do
    Subscription.all.each do |subscription|
      assert_equal (subscription.package.product.prices.first.price * 730.0).round(4), subscription.run_rate
    end
  end

  test 'can collect usage on pause' do

    sp = subscription_products :wordpress_package

    timestamp = Time.now

    sp.pause!

    assert sp.billing_usages.where("created_at >= ?", timestamp).exists?
    refute sp.billing_usages.where("created_at >= ?", timestamp).first.total.zero?
    refute sp.billing_usages.where("created_at >= ?", timestamp).first.processed

  end


end
