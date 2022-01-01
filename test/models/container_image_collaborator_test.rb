require "test_helper"

class ContainerImageCollaboratorTest < ActiveSupport::TestCase

  test 'can list collaborated images' do

    wp = container_images :custom
    refute_includes ContainerImage.find_all_for(users(:user)), wp

    wp.container_image_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    # Not active yet
    refute_includes ContainerImage.find_all_for(users(:user)), wp

    wp.container_image_collaborators.first.update active: true

    assert_includes ContainerImage.find_all_for(users(:user)), wp

    wp.container_image_collaborators.delete_all

  end

  test 'can add collaborators' do

    wp = container_images :custom
    u = users :user
    refute wp.can_view? u
    refute wp.can_edit? u

    wp.container_image_collaborators.create! current_user: users(:admin), collaborator: u

    refute wp.can_view? u
    refute wp.can_edit? u

    wp.container_image_collaborators.first.update active: true

    assert wp.can_view? u
    assert wp.can_edit? u

    wp.container_image_collaborators.delete_all

  end

  test 'can view public image' do

    wp = container_images :wordpress
    u = users :user
    assert wp.can_view? u
    refute wp.can_edit? u

  end

end
