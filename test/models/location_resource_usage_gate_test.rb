require "test_helper"

# Covers Location#resource_usage_required? and its effect inside #next_region.
#
# Region#current_allocated_usage costs an aggregate query PLUS two Prometheus reads per
# node, and against a zone on another continent a read is ~0.6s -- the most expensive
# thing on the order path. Under a "least" + fill_by_qty location with both overcommit
# flags on, nothing in #next_region ever reads the result, so it is not computed.
#
# The point of these tests is that skipping it changes NO placement decision.
class LocationResourceUsageGateTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  test "not required when overcommit is on and zones are ranked by quantity" do
    refute build_location(fill_by_qty: true).resource_usage_required?
  end

  test "required when ranking by resources rather than quantity" do
    assert build_location(fill_by_qty: false).resource_usage_required?
  end

  test "required when the cpu capacity gate is active" do
    assert build_location(fill_by_qty: true, overcommit_cpu: false).resource_usage_required?
  end

  test "required when the memory capacity gate is active" do
    assert build_location(fill_by_qty: true, overcommit_memory: false).resource_usage_required?
  end

  test "required for the fill-to-full strategy, which always ranks by resources" do
    assert build_location(fill_by_qty: true, fill_strategy: "full").resource_usage_required?
  end

  test "next_region issues no capacity sum when the figure cannot be read" do
    location = build_location(fill_by_qty: true)
    regions = build_regions(location)

    assert_equal 0, capacity_sums { location.next_region([], @user) }
    assert_includes regions, location.next_region([], @user)
  end

  test "next_region still computes the figure when a gate needs it" do
    location = build_location(fill_by_qty: true, overcommit_cpu: false)
    build_regions(location)

    assert_operator capacity_sums { location.next_region([], @user) }, :>, 0
  end

  test "the chosen zone is the same whether or not the figure is computed" do
    location = build_location(fill_by_qty: true)
    build_regions(location)

    skipped = location.next_region([], @user)
    refute_nil skipped

    # Same location, same zones. Switching a capacity gate on forces the figure to be
    # computed; with empty zones the gate cannot reject anything, so the choice must be
    # identical. This is what makes the guard a pure omission rather than a policy change.
    location.update!(overcommit_cpu: false)
    computed = location.reload.next_region([], @user)

    assert_equal skipped, computed
  end

  # --- the gate itself, with a non-zero committed figure ------------------------------
  #
  # Everything above proves the figure is or is not COMPUTED. These prove it is USED:
  # replace Deployment::Container.allocated_resources with a constant zero and these are
  # the tests that fail.

  # Single zone throughout, deliberately. With two zones, fill_by_qty picks the one
  # holding fewer containers and the assertion passes whether or not the gate did
  # anything -- these tests would then survive an aggregate that always returned zero.

  test "a zone with no cpu left is rejected when the cpu gate is active" do
    location = build_location(fill_by_qty: true, overcommit_cpu: false)
    only = build_regions(location, count: 1).first

    # metric_cpu_cores is a fixed 2 cores per node under Rails.env.test?, and an empty
    # packages array makes next_region ask for 1 cpu / 512 MB. Commit both cores.
    fill_region(only, cpu: 2, memory: 256)

    assert_nil location.next_region([], @user)
  end

  test "a zone with no memory left is rejected when the memory gate is active" do
    location = build_location(fill_by_qty: true, overcommit_memory: false)
    only = build_regions(location, count: 1).first

    # 2048 MB per node in test; the request is 512 MB.
    fill_region(only, cpu: 0.1, memory: 2048)

    assert_nil location.next_region([], @user)
  end

  test "a partially committed zone is not wrongly excluded" do
    location = build_location(fill_by_qty: true, overcommit_cpu: false)
    # One zone only, so this isolates the gate from the ranking: with two zones the
    # emptier one would win on container count and prove nothing about the gate.
    only = build_regions(location, count: 1).first

    fill_region(only, cpu: 0.5, memory: 128)

    assert_equal only, location.next_region([], @user)
  end

  private

  # Put one container carrying the given resources into the region, the way
  # ProvisionServices::ContainerProvisioner does (cpu/memory written onto the row).
  def fill_region(region, cpu:, memory:)
    project = Deployment.create!(user: @user, name: "gate_#{SecureRandom.hex(4)}")
    service = project.services.create!(
      name: "svc#{SecureRandom.hex(3)}",
      container_image: ContainerImage.first,
      region: region
    )
    service.containers.create!(
      name: "c#{SecureRandom.hex(3)}",
      node: region.nodes.first,
      cpu: cpu,
      memory: memory
    )
  end

  def build_location(fill_by_qty:, overcommit_cpu: true, overcommit_memory: true,
    fill_strategy: "least", name: nil)
    Location.create!(
      name: name || "gate_#{SecureRandom.hex(4)}",
      active: true,
      fill_strategy: fill_strategy,
      fill_by_qty: fill_by_qty,
      overcommit_cpu: overcommit_cpu,
      overcommit_memory: overcommit_memory
    )
  end

  # Two empty zones, each with one node, both visible to the user's group.
  def build_regions(location, count: 2)
    %w[a b].first(count).map do |suffix|
      region = location.regions.create!(name: "#{location.name}-#{suffix}")
      @user.user_group.regions << region
      region.nodes.create!(
        active: true,
        label: "#{location.name}-#{suffix}-n1",
        hostname: "#{location.name}-#{suffix}-n1"
      )
      region
    end
  end

  # Count the aggregate issued by Deployment::Container.allocated_resources.
  def capacity_sums
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 if payload[:sql].to_s.include?('SUM("deployment_containers"."cpu")')
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
