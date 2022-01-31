require 'test_helper'

class ServiceProvisionFlowTest < ActionDispatch::IntegrationTest

  test 'can provision new Wordpress service' do

    # Build order session
    order_session = OrderSession.new users(:admin)
    order_session.add_image container_images(:wordpress)
    order_session.project.name = 'Test Order'

    order_session.images.each do |image|
      image[:package_id] = products(:containersmall).id
      next unless image[:container_name] == 'Wordpress'
      image[:params]['username'][:value] = 'devuser'
    end

    # Create Order
    audit = Audit.create!(
      user: users(:admin),
      ip_addr: '127.0.0.1',
      event: 'created'
    )
    build_order = BuildOrderService.new(audit, order_session.to_order)
    build_order.process_order = false

    prep_order_success = build_order.perform
    puts build_order.errors.join(" ")
    assert prep_order_success

    order = build_order.order
    assert_kind_of Order, order

    # lb_timestamp = load_balancers(:default).job_performed

    # Process Order
    event = EventLog.create!(
      locale: 'order.provision',
      event_code: '0a3af01a3384fa10',
      audit: audit,
      status: 'pending'
    )
    order.current_event = event
    order_process = ProcessOrderService.new(order)

    Sidekiq::Testing.inline! do
      order_prov_success = order_process.perform
      puts order_process.errors.join(" ") unless order_process.errors.empty?
      assert order_prov_success
    end

    project = order.deployment

    refute_nil project

    refute_empty project.services
    refute_empty project.deployed_containers
    refute_empty project.domains

    # Test Container Configuration
    project.deployed_containers.each do |c|
      assert_kind_of Hash, c.runtime_config
    end

    # Test service settings
    wordpress_service = project.services.where( container_images: { name: 'wordpress' } ).joins(:container_image).first
    # Tests that the default value is correctly applied when user supplies no value
    assert_equal(
      wordpress_service.container_image.setting_params.find_by(name: 'title').value,
      wordpress_service.setting_params.find_by(name: 'title').value
    )

    # Ensure proper region
    assert_equal build_order.region, wordpress_service.region

    # Tests that a user-supplied value is correctly stored
    assert_equal 'devuser', wordpress_service.setting_params.find_by(name: 'username').value

    # Ensure LoadBalancer was reloaded
    # refute_equal lb_timestamp, load_balancers(:default).job_performed

    # Ensure subscription was setup correctly
    project.services.each do |service|
      refute_nil service.package
    end


  end
end
