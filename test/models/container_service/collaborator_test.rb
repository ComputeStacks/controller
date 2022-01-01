require 'test_helper'

class ContainerService::CollaboratorTest < ActiveSupport::TestCase

  test 'collaborator can view container service' do

    s = Deployment::ContainerService.first
    u = User.where.not(id: s.user.id).first

    refute_includes Deployment::ContainerService.find_all_for(u), s

    s.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: u

    refute_includes Deployment::ContainerService.find_all_for(u), s

    s.deployment.deployment_collaborators.first.update active: true

    assert_includes Deployment::ContainerService.find_all_for(u), s

    s.deployment.deployment_collaborators.delete_all

  end

end
