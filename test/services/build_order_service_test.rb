require 'test_helper'

class BuildOrderServiceTest < ActiveSupport::TestCase

  test 'can generate an order' do
    order_session = OrderSession.new users(:admin)
    order_session.project.name = 'Test'
    order_session.add_image container_image_image_variants(:wordpress_default)
    order_session.images.each do |i|
      i[:package_id] = products(:containersmall).id
    end
    order_session.location = locations(:testlocation)
    order_session.save
    refute_nil order_session.location

    # `order_session` has no region just yet
    session_check_one = OrderSession.new(users(:admin), order_session.id)
    refute_nil session_check_one.region
    session_check_one.save

    assert_equal session_check_one.region, OrderSession.new(users(:admin), order_session.id).region

    order_builder = BuildOrderService.new(
      Audit.create!(
        user: users(:admin),
        ip_addr: '127.0.0.1',
        event: 'created'
      ),
      order_session.to_order
    )
    order_builder.process_order = false
    assert order_builder.perform
    refute_nil order_builder.order
    refute_nil order_builder.region

  end

end
