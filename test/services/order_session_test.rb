require 'test_helper'

class OrderSessionTest < ActiveSupport::TestCase

  setup do
    @order_session = OrderSession.new users(:admin)
  end

  test 'can add images' do
    @order_session.add_image container_images(:wordpress)
    assert_includes @order_session.images.map { |i| i[:container_id] }, container_images(:wordpress).id

    # MariaDB is required by Wordpress, so ensure we also have that
    assert_includes @order_session.images.map { |i| i[:container_id] }, container_images(:mariadb).id
  end

  test 'can find existing order' do
    assert_equal OrderSession.new(users(:admin), @order_session.id).id, @order_session.id
  end

  test 'can generate valid order' do
    @order_session.add_image container_images(:elasticsearch)
    order_data = @order_session.to_order
    refute_empty order_data[:containers]
    assert_includes order_data[:containers].map { |i| i[:image_id] }, container_images(:elasticsearch).id
  end

end
