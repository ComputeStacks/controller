require "test_helper"

class ContainerRegistryCollaboratorTest < ActiveSupport::TestCase

  test 'can list collaborated registries' do

    r = ContainerRegistry.first

    refute_includes ContainerRegistry.find_all_for(users(:user)), r

    r.container_registry_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    refute_includes ContainerRegistry.find_all_for(users(:user)), r

    r.container_registry_collaborators.first.update active: true

    assert_includes ContainerRegistry.find_all_for(users(:user)), r

    r.container_registry_collaborators.delete_all

  end

  test 'can add collaborator' do

    r = ContainerRegistry.first
    u = User.where.not(id: r.user.id).first

    refute r.can_view?(u)

    r.container_registry_collaborators.create! current_user: users(:admin), collaborator: u

    refute r.can_view?(u)

    r.container_registry_collaborators.first.update active: true

    assert r.can_view?(u)

    r.container_registry_collaborators.delete_all

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

    r = ContainerRegistry.first
    admin = users(:admin)
    r.container_registry_collaborators.create! current_user: admin, collaborator: u

    assert r.container_registry_collaborators.where(user_id: u.id).exists?
    u.current_user = admin
    u.destroy

    refute r.container_registry_collaborators.where(user_id: u.id).exists?

  end

end
