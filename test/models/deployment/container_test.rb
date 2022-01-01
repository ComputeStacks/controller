require 'test_helper'

class Deployment::ContainerTest < ActiveSupport::TestCase

  test 'can list all containers' do

    c = Deployment::Container.first
    u = c.user

    assert_includes Deployment::Container.find_all_for(u), c

  end

  test 'collaborators can view containers too' do

    c = Deployment::Container.first
    u = User.where.not(id: c.user.id).first

    refute_includes Deployment::Container.find_all_for(u), c

    c.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: u

    refute_includes Deployment::Container.find_all_for(u), c

    c.deployment.deployment_collaborators.first.update active: true

    assert_includes Deployment::Container.find_all_for(u), c

    c.deployment.deployment_collaborators.delete_all

  end

end
