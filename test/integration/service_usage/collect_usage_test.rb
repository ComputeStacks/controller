require 'test_helper'

class CollectUsageTest < ActionDispatch::IntegrationTest

  include ConsulTestContainerConcern

  test 'correct amounts are stored' do
    BillingUsage.delete_all
    BillingUsageServices::CollectUsageService.new.perform

    # Note: This currently assumes 1 container per service.
    BillingUsage.all.each do |i|

      refute i.processed if i.total.positive?

      # We must have a subscription product!
      refute_nil i.subscription_product

      # Verify price is correctly stored
      current_price = i.subscription_product.current_price(i.qty)
      refute_nil current_price
      assert_equal current_price.price.to_f, i.rate

      ##
      # Verify total is correct

      # Convert time difference into fractional hour.
      period_length = ((i.period_end - i.period_start).to_f / 1.hour).round(4)

      # Multiply price by fractional hour to get adjusted price, then multiply by quantity.
      usage_total = ((current_price.price * period_length) * i.qty).round(8)

      assert_equal i.total, usage_total

      ##
      # Individual resource types
      case i.product.resource_kind
      when 'backup'
        # Note about `inject`: We need to add the `(0)` part to make sure that's the first element, otherwise the first `id` won't be multiplied by `1024`.
        expected_amount = i.subscription.linked_obj.service.volumes.pluck(:id).inject(0) do |sum, id|
          # we are multiply the id * 1024 to generate fake usage data.
          sum + (id * 1024)
        end
        expected_amount = expected_amount.zero? ? expected_amount : (expected_amount / BYTE_TO_GB).round(4)
        puts "ID: #{i.id} | E: #{expected_amount} | A: #{i.qty}" if expected_amount != i.qty
        assert_equal expected_amount, i.qty
      when 'storage'
        next if i.subscription.linked_obj.service.volumes.empty?

        # add all IDs together
        expected_usage = i.subscription.linked_obj.service.volumes.pluck(:id).inject(:+)
        # deduct what's included in their plan
        expected_usage -= i.subscription.package.storage
        puts "ID: #{i.id} | E: #{expected_usage} | A: #{i.qty}" if expected_usage != i.qty
        assert_equal expected_usage, i.qty
      end

    end
  end

end
