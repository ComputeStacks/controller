require "test_helper"

class Dns::ZoneFindCoveringTest < ActiveSupport::TestCase
  test "finds a zone by its own name" do
    assert_equal dns_zones(:app), Dns::Zone.find_covering("cs.local")
    assert_equal dns_zones(:user_zone), Dns::Zone.find_covering("foo.local")
  end

  test "finds the zone covering a subdomain" do
    assert_equal dns_zones(:user_zone), Dns::Zone.find_covering("www.foo.local")
    assert_equal dns_zones(:user_zone), Dns::Zone.find_covering("a.b.c.foo.local")
  end

  test "returns the shortest matching zone first" do
    Dns::Zone.create!(name: "sub.foo.local", skip_provision_driver: true)
    assert_equal dns_zones(:user_zone), Dns::Zone.find_covering("www.sub.foo.local")
  end

  test "finds a deeper zone when no shorter one exists" do
    deep = Dns::Zone.create!(name: "sub.bar.local", skip_provision_driver: true)
    assert_equal deep, Dns::Zone.find_covering("www.sub.bar.local")
  end

  test "returns nil when no zone covers the name" do
    assert_nil Dns::Zone.find_covering("example.com")
    assert_nil Dns::Zone.find_covering("www.nothere.local")
  end
end
