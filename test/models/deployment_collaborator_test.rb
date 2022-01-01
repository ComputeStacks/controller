require "test_helper"

class DeploymentCollaboratorTest < ActiveSupport::TestCase

  test 'can list collaborations' do

    d = Deployment.first
    u = User.where.not(id: d.user.id).first

    refute_includes Deployment.find_all_for(u), d

    d.deployment_collaborators.create! current_user: users(:admin), collaborator: u

    refute_includes Deployment.find_all_for(u), d

    d.deployment_collaborators.first.update active: true

    assert_includes Deployment.find_all_for(u), d

    d.deployment_collaborators.delete_all

  end

  test 'can add collaborator' do

    d = Deployment.first
    i = d.container_images.first
    v = d.volumes.first
    s = d.services.first
    c = d.deployed_containers.first
    u = User.where.not(id: d.user.id).first

    refute d.can_view?(u)
    assert i.can_view?(u)
    refute i.can_edit?(u)
    refute s.can_view?(u)
    refute c.can_view?(u)
    refute v.can_view?(u)

    d.deployment_collaborators.create! current_user: users(:admin), collaborator: u

    refute d.can_view?(u)
    assert i.can_view?(u)
    refute i.can_edit?(u)
    refute s.can_view?(u)
    refute c.can_view?(u)
    refute v.can_view?(u)

    d.deployment_collaborators.first.update active: true

    assert d.can_view?(u)
    assert i.can_view?(u)
    refute i.can_edit?(u)
    assert s.can_view?(u)
    assert c.can_view?(u)
    assert v.can_view?(u)

    d.deployment_collaborators.delete_all

  end

end
