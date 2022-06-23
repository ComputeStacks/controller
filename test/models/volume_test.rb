require 'test_helper'

class VolumeTest < ActiveSupport::TestCase

  test 'can list all owned volumes' do

    v = Volume.where.not(user: nil).first
    u = v.user

    assert_includes Volume.find_all_for(u), v

  end

  test 'can list collaborated volumes' do

    v = volumes :wordpress_web
    u = users :user

    refute_includes Volume.find_all_for(u), v

    puts

    v.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: u

    refute_includes Volume.find_all_for(u), v

    v.deployment.deployment_collaborators.first.update active: true

    assert_includes Volume.find_all_for(u), v

    v.deployment.deployment_collaborators.delete_all

  end

end
