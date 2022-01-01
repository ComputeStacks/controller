require 'test_helper'

class UsersHelperTest < ActionView::TestCase

  test 'lookup country by ip' do
    assert_equal 'CA', country_by_ip('198.100.144.26')
    assert_equal 'US', country_by_ip('173.87.35.138')
  end

end