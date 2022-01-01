require "test_helper"

class Dns::ZoneCollaboratorTest < ActiveSupport::TestCase

  test 'can list collaborated zones' do

    z = dns_zones :user_zone

    refute_includes Dns::Zone.find_all_for(users(:user)), z

    z.dns_zone_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    refute_includes Dns::Zone.find_all_for(users(:user)), z

    z.dns_zone_collaborators.first.update active: true

    assert_includes Dns::Zone.find_all_for(users(:user)), z

    z.dns_zone_collaborators.delete_all

  end

  ##
  # TODO: Wait until provision driver has ben rewritten.
  #       Will fail until provision_driver is no longer nil.
  # test 'can add collaborator' do
  #   zone = dns_zones :user_zone
  #
  #   refute zone.can_view?(users(:user))
  #
  #   zone.dns_zone_collaborators.create! current_user: users(:admin), collaborator: users(:user)
  #
  #   assert zone.can_view?(users(:user))
  #
  # end

end
