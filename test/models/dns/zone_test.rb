require "test_helper"

class Dns::ZoneTest < ActiveSupport::TestCase

  test 'can list zones' do

    z = Dns::Zone.where.not(user: nil).first
    u = z.user

    assert_includes Dns::Zone.find_all_for(u), z

  end

end
