require "test_helper"

class BillingPlanTest < ActiveSupport::TestCase
  setup do
    @billing_plan = BillingPlan.create!(name: "tester1")
  end

  test "add products to billing plan" do
    package_a_product = Product.create!(
      name: "container_s",
      label: "ContainerS",
      kind: "package"
    )
    package_a_product.create_package(
      cpu: 1,
      memory: 512,
      storage: 10,
      bandwidth: 3000,
      local_disk: 1
    )
    package_a_resource = @billing_plan.billing_resources.create!(product: package_a_product)
    package_a_resource.prices.create!(price: 0.00343, term: "hour", currency: "USD", billing_phase: package_a_resource.billing_phases.first, regions: Region.all)

    refute_nil package_a_resource.id
    refute_empty package_a_resource.prices
  end

  test "add product with price tiers" do
    bandwidth_product = Product.create!(
      name: "bandwidth",
      label: "Bandwidth",
      kind: "resource",
      unit: 1,
      unit_type: "GB",
      resource_kind: "bandwidth",
      is_aggregated: true # Once you used it, you pay for it.
    )
    bandwidth_resource = @billing_plan.billing_resources.create!(product: bandwidth_product)
    bandwidth_resource.prices.create!(price: 0, max_qty: 1024, currency: "USD", billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # First 1TB is free
    bandwidth_resource.prices.create!(price: 0.09, max_qty: 10240, currency: "USD", billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 1TB - 10TB
    bandwidth_resource.prices.create!(price: 0.07, max_qty: nil, currency: "USD", billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 10TB+

    refute_nil bandwidth_resource.id
    assert_equal 3, bandwidth_resource.prices.count
  end

  test "available? and missing_required_products agree for a complete plan" do
    plan = billing_plans(:default)
    assert_operator plan.users.count, :>, 1,
      "fixtures must put several users on one plan, or the dedupe assertions below prove nothing"

    assert_empty plan.missing_required_products
    assert plan.available?
    assert_empty BillingPlan.invalid_plans
  end

  test "missing_required_products lists absent resource_kinds in declared order" do
    @billing_plan.billing_resources.create!(product: products(:bandwidth))

    assert_equal %w[storage local_disk], @billing_plan.missing_required_products
    refute @billing_plan.available?
  end

  test "invalid_plans reports an incomplete plan once, not once per user" do
    users(:user).user_group.update!(billing_plan: @billing_plan)
    assert_operator @billing_plan.users.count, :>, 1,
      "need multiple users on the incomplete plan to catch a missing distinct"

    assert_equal [@billing_plan], BillingPlan.invalid_plans
  end

  test "invalid_plans ignores incomplete plans that no user is on" do
    assert_empty @billing_plan.users
    refute @billing_plan.available?

    assert_empty BillingPlan.invalid_plans
  end

  test "invalid_plans query count does not scale with the number of users" do
    users(:user).user_group.update!(billing_plan: @billing_plan)
    users(:admin).user_group.update!(billing_plan: @billing_plan)
    assert_equal 4, @billing_plan.users.count

    queries = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name].to_s)
      queries << payload[:sql]
    end
    begin
      assert_equal [@billing_plan], BillingPlan.invalid_plans
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    # One pluck of resource_kinds, one load of the in-use plans. The row-at-a-time
    # version needed 3 Product.lookup round trips per USER instead.
    assert_equal 2, queries.count, "expected 2 queries, got:\n#{queries.join("\n")}"
  end
end
