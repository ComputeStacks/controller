require 'test_helper'

class ContainerImageTest < ActiveSupport::TestCase

  test "can list images" do

    image = ContainerImage.where.not(user: nil).first
    u = image.user

    assert_includes ContainerImage.find_all_for(u), image

  end

  test 'can list public images' do

    u = users(:user)

    assert_empty ContainerImage.find_all_for u
    refute_empty ContainerImage.find_all_for u, true

  end

  test "can clone image" do
    user = User.find_by(is_admin: true) # Grab an admin user!
    assert_not_nil user

    parent_image = ContainerImage.find_by(name: 'wordpress')
    assert_not_nil parent_image

    new_image = parent_image.dup
    new_image.registry_image_tag = parent_image.default_variant.registry_image_tag
    new_image.current_user = user
    new_image.name = "#{parent_image.name}-clone"
    new_image.label = "#{parent_image.label}-clone"
    new_image.parent_image_id = parent_image.id

    assert new_image.save

    error_event = SystemEvent.find_by(event_code: "#{new_image.id}-2a88db8ed4539a18")
    puts error_event.data if error_event
    assert_nil error_event

    assert new_image.env_params.count == parent_image.env_params.count
  end

  test 'test image authorization' do

    wp = container_images :wordpress
    u = users :user
    assert wp.can_view? u
    refute wp.can_edit? u

  end

end
