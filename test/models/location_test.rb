require 'test_helper'

class LocationTest < ActiveSupport::TestCase

  test 'can find next region' do
    admin_user = users(:admin)

    location = Location.create!(
      name: "test_find_region",
      active: true,
      fill_strategy: "least",
      fill_by_qty: true,
      overcommit_cpu: true,
      overcommit_memory: true
    )

    region_one = location.regions.create!( name: "r01" )
    region_two = location.regions.create!( name: "r02" )
    region_three = location.regions.create!( name: "r03" )

    admin_user.user_group.regions << region_one
    admin_user.user_group.regions << region_two
    admin_user.user_group.regions << region_three

    region_one.nodes.create!( active: true, label: 'node101', hostname: 'node101' )
    region_one.nodes.create!( active: true, label: 'node102', hostname: 'node102' )
    region_one.nodes.create!( active: true, label: 'node103', hostname: 'node103' )

    region_two.nodes.create!( active: true, label: 'node111', hostname: 'node111' )
    region_two.nodes.create!( active: true, label: 'node112', hostname: 'node112' )
    region_two.nodes.create!( active: true, label: 'node113', hostname: 'node113' )

    region_three.nodes.create!( active: true, label: 'node121', hostname: 'node121' )
    region_three.nodes.create!( active: true, label: 'node122', hostname: 'node122' )
    region_three.nodes.create!( active: true, label: 'node123', hostname: 'node123' )

    packages = BillingPackage.all.map { |i| i } # get an array, not an AR collection.

    assert_equal 9, location.nodes.count

    assert_equal region_one, location.next_region(packages, admin_user)

    ##
    # r1 Service
    project_r1 = Deployment.create!(user: admin_user, name: "regon_one_project")
    service_r1 = project_r1.services.create!(name: "foobar_r1", container_image: ContainerImage.first, region: region_one)
    subscription_r1 = admin_user.subscriptions.create!(active: true)
    subscription_r1.subscription_products.create!(product: products(:containerm), allow_nil_phase: true)
    service_r1.containers.create!(name: "foobar_r1_1", node: region_one.find_node(subscription_r1.package), subscription: subscription_r1)

    ##
    # Ensure QTY based chooses correctly
    assert_equal region_two, location.next_region(packages, admin_user)
    assert_equal Node.find_by(hostname: 'node102'), region_one.find_node(subscription_r1.package)
    location.update fill_strategy: 'full'
    assert_equal region_one, location.next_region(packages, admin_user)
    assert_equal Node.find_by(hostname: 'node101'), region_one.find_node(subscription_r1.package)

    ##
    # Ensure Resource based chooses correctly
    location.update fill_by_qty: false, fill_strategy: 'least'
    assert_equal region_two, location.next_region(packages, admin_user)
    assert_equal Node.find_by(hostname: 'node102'), region_one.find_node(subscription_r1.package)
    location.update fill_strategy: 'full'
    assert_equal region_one, location.next_region(packages, admin_user)
    assert_equal Node.find_by(hostname: 'node101'), region_one.find_node(subscription_r1.package)


  end

end
