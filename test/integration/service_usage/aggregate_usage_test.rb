require 'test_helper'

class AggregateUsageTest < ActionDispatch::IntegrationTest

  include ConsulTestContainerConcern

  test 'can aggregate usage' do

    VCR.use_cassette('aggregate_usage') do

      # Clean up and refresh
      BillingUsage.delete_all
      BillingUsageServices::CollectUsageService.new.perform

      ag_service = BillingUsageServices::AggregateUsageService.new(false)
      ag_service.perform

      refute_empty ag_service.result

      ag_service.result.each do |group|

        ##
        # Basic sanity checking
        expected_keys = %w(
          subscription_id
          subscription_product_id
          product
          billing_resource
          container_service_id
          container_id
          user
          external_id
          total
          qty
          period_start
          period_end
          usage_items
        )
        assert_empty expected_keys - group.keys

        refute_nil group.dig(:product, :id)
        refute_nil group.dig(:user, :id)
        refute_nil group.dig(:billing_resource, :id)

        group.keys.each do |k|
          next if k == "external_id"
          refute_nil group[k]
        end

        refute_empty group[:usage_items]

        assert_instance_of Time, group[:period_start]
        assert_instance_of Time, group[:period_end]

        assert group[:period_start] < group[:period_end]

        ##
        # Test our final qty/totals match up
        sub_usage = BillingUsage.where(subscription_product_id: group[:subscription_product_id])
        refute_empty sub_usage
        expected_qty = sub_usage.pluck(:qty).inject { |sum, i| sum + i }
        expected_total = sub_usage.pluck(:total).inject { |sum, i| sum + i }

        # Added the `.to_s` here because we sometimes had failing tests with:
        #
        #     test_can_aggregate_usage
        #        Expected: 0.87538033714e3
        #          Actual: 875.38033714
        #
        assert_equal expected_qty.to_s, group[:qty].to_s
        assert_equal expected_total.to_s, group[:total].to_s

        ##
        # Match up our user
        assert_equal Subscription.find(group[:subscription_id]).user, User.find(group[:user][:id])
      end
    end

  end

end
