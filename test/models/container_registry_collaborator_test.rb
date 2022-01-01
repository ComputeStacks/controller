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

end
