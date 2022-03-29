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

  test 'delete user also deletes collaborator record' do

    u = User.new(
      fname: "jimmy",
      lname: "little",
      email: "jlittle@example.net",
      password: "foobar5%532",
      password_confirmation: "foobar5%532",
      is_admin: false,
      country: "US"
    )
    u.skip_confirmation!
    u.save

    wp = container_images :wordpress
    admin = users(:admin)
    wp.container_image_collaborators.create! current_user: admin, collaborator: u

    assert wp.container_image_collaborators.where(user_id: u.id).exists?
    u.current_user = admin
    u.destroy

    refute wp.container_image_collaborators.where(user_id: u.id).exists?

  end

end
