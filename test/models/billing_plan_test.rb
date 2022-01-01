require 'test_helper'

class BillingPlanTest < ActiveSupport::TestCase

  setup do
    @billing_plan = BillingPlan.create!(name: 'tester1')
  end

  test 'add products to billing plan' do

    package_a_product = Product.create!(
        name: 'container_s',
        label: 'ContainerS',
        kind: 'package'
    )
    package_a_product.create_package(
        cpu: 1,
        memory: 512,
        storage: 10,
        bandwidth: 3000,
        local_disk: 1
    )
    package_a_resource = @billing_plan.billing_resources.create!(product: package_a_product)
    package_a_resource.prices.create!(price: 0.00343, term: 'hour', currency: 'USD', billing_phase: package_a_resource.billing_phases.first, regions: Region.all)

    refute_nil package_a_resource.id
    refute_empty package_a_resource.prices

  end

  test 'add product with price tiers' do
    bandwidth_product = Product.create!(
        name: 'bandwidth',
        label: 'Bandwidth',
        kind: 'resource',
        unit: 1,
        unit_type: 'GB',
        resource_kind: 'bandwidth',
        is_aggregated: true # Once you used it, you pay for it.
    )
    bandwidth_resource = @billing_plan.billing_resources.create!(product: bandwidth_product)
    bandwidth_resource.prices.create!(price: 0, max_qty: 1024, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # First 1TB is free
    bandwidth_resource.prices.create!(price: 0.09, max_qty: 10240, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 1TB - 10TB
    bandwidth_resource.prices.create!(price: 0.07, max_qty: nil, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 10TB+

    refute_nil bandwidth_resource.id
    assert_equal 3, bandwidth_resource.prices.count

  end

end
