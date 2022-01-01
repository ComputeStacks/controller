require 'test_helper'

class ContainerRegistryTest < ActiveSupport::TestCase

  test "can list container registries" do

    r = ContainerRegistry.first
    u = r.user

    assert_includes ContainerRegistry.find_all_for(u), r

  end

  test "can create new registry and provider" do
    new_reg = ContainerRegistry.new(label: "My Registry!")
    assert new_reg.save
    puts new_reg.errors.full_messages unless new_reg.errors.empty?
    new_reg.reload
    assert_not_nil new_reg.container_image_provider
    assert new_reg.container_image_provider.name == new_reg.name

    refute new_reg.can_view? users(:user)

    new_reg.container_registry_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    refute new_reg.can_view? users(:user)

    new_reg.container_registry_collaborators.first.update active: true

    assert new_reg.can_view? users(:user)

    new_reg.container_registry_collaborators.delete_all

  end

end
