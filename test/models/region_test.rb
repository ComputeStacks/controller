require "test_helper"

class RegionTest < ActiveSupport::TestCase
  setup do
    @region = regions(:regionone)
  end

  test "ipv6_egress defaults to false" do
    assert_equal({}, @region.features)
    assert_equal false, @region.ipv6_egress
    assert_equal false, @region.ipv6_egress?
  end

  test "ipv6_egress is false when features is nil" do
    @region.features = nil

    assert_equal false, @region.ipv6_egress
    assert_equal false, @region.ipv6_egress?
  end

  test "ipv6_egress is false when features is not a hash" do
    @region.features = []

    assert_equal false, @region.ipv6_egress
  end

  test "ipv6_egress round trips through save and reload" do
    @region.ipv6_egress = true

    assert @region.save
    @region.reload

    assert_equal true, @region.ipv6_egress
    assert_equal true, @region.ipv6_egress?
    assert_equal true, @region.features["ipv6_egress"]
    assert_equal true, Region.find(@region.id).ipv6_egress
  end

  test "ipv6_egress can be turned back off and persists" do
    @region.update! ipv6_egress: true
    @region.reload

    @region.update! ipv6_egress: false
    @region.reload

    assert_equal false, @region.ipv6_egress
    assert_equal false, @region.features["ipv6_egress"]
  end

  test "ipv6_egress casts checkbox strings" do
    @region.ipv6_egress = "1"
    assert_equal true, @region.ipv6_egress

    @region.ipv6_egress = "0"
    assert_equal false, @region.ipv6_egress

    @region.ipv6_egress = ""
    assert_equal false, @region.ipv6_egress

    @region.ipv6_egress = nil
    assert_equal false, @region.ipv6_egress
  end

  test "ipv6_egress= always stores a real boolean" do
    @region.ipv6_egress = "1"
    assert_equal true, @region.features["ipv6_egress"]

    @region.ipv6_egress = nil
    assert_equal false, @region.features["ipv6_egress"]
  end

  test "ipv6_egress= does not clobber other feature keys" do
    @region.features = {"ptr" => "some-driver", "container_shared_storage" => true}
    @region.ipv6_egress = true

    assert @region.save
    @region.reload

    assert_equal "some-driver", @region.features["ptr"]
    assert_equal true, @region.features["container_shared_storage"]
    assert_equal true, @region.features["ipv6_egress"]
  end

  test "ipv6_egress= initializes features when nil" do
    @region.features = nil
    @region.ipv6_egress = true

    assert_equal({"ipv6_egress" => true}, @region.features)
  end

  test "ipv6_egress reads a truthy value written directly into features" do
    @region.features = {"ipv6_egress" => "true"}

    assert_equal true, @region.ipv6_egress
  end
end
