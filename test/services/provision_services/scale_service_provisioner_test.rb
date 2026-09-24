require "test_helper"
require "minitest/mock"

class ProvisionServices::ScaleServiceProvisionerTest < ActiveSupport::TestCase
  setup do
    # :wordpress maps to the wordpress image, which is can_scale: true.
    @service = deployment_container_services(:wordpress)
    @audit = Audit.create_from_object!(@service, "scale", "127.0.0.1", users(:admin))
  end

  def build_event(to)
    EventLog.create!(
      locale: "service.scale",
      locale_keys: {to: to},
      status: "running",
      event_code: "test",
      audit: @audit
    )
  end

  # The reported bug (event 16fb2bd5a38082ee): scaling DOWN was cancelled with
  # "Network size can not accommodate the requested number of containers." even
  # though a scale-down frees addresses and needs no new ones.
  test "scaling down is not blocked when the private network is full" do
    event = build_event(2)
    prov = ProvisionServices::ScaleServiceProvisioner.new(@service, event, 2)
    # Simulate 4 running containers (scale 4 -> 2) on a completely full private network.
    @service.stub(:containers, Struct.new(:count).new(4)) do
      @service.deployment.stub(:private_network, networks(:netone)) do
        # addresses_available: 0 is what made the old `(qty + current_count)` formula
        # cancel here; the fixed code skips the check entirely for a scale-down.
        networks(:netone).stub(:addresses_available, 0) do
          assert prov.send(:valid?), "scale-down must not be blocked by network capacity"
        end
      end
    end
    assert_not event.cancelled?
  end

  # Scaling up by exactly the number of free addresses must be allowed (the `<=`
  # boundary), exercised end-to-end through valid?. This is the autoscaler's path
  # when it adds the last container that fits.
  test "scaling up that exactly fills the network is allowed" do
    event = build_event(6)
    prov = ProvisionServices::ScaleServiceProvisioner.new(@service, event, 6)
    @service.stub(:containers, Struct.new(:count).new(4)) do
      @service.user.stub(:can_order_containers?, true) do
        @service.deployment.stub(:private_network, networks(:netone)) do
          networks(:netone).stub(:addresses_available, 2) do # delta 2 == free 2
            assert prov.send(:valid?), "scale-up that exactly fits must be allowed"
          end
        end
      end
    end
    assert_not event.cancelled?
  end

  # Pure predicate: the threshold math, including the exact-fit boundary.
  test "network_has_capacity_for? compares the delta against free addresses" do
    prov = ProvisionServices::ScaleServiceProvisioner.new(@service, build_event(2), 2)
    net = networks(:netone)
    avail = net.addresses_available

    assert prov.send(:network_has_capacity_for?, net, avail), "exact fit must be allowed"
    assert prov.send(:network_has_capacity_for?, net, avail - 1)
    assert_not prov.send(:network_has_capacity_for?, net, avail + 1), "over capacity must be rejected"
    assert prov.send(:network_has_capacity_for?, nil, 9_999), "no private network is always allowed"
  end

  # Scaling up beyond the network's free space is still cancelled. Quota is stubbed
  # so the network guard (not the quota guard) is what fires.
  test "scaling up beyond network capacity is cancelled" do
    event = build_event(9)
    prov = ProvisionServices::ScaleServiceProvisioner.new(@service, event, 9)
    @service.stub(:containers, Struct.new(:count).new(4)) do
      @service.user.stub(:can_order_containers?, true) do
        @service.deployment.stub(:private_network, networks(:netone)) do
          networks(:netone).stub(:addresses_available, 0) do
            assert_not prov.send(:valid?)
          end
        end
      end
    end
    assert event.cancelled?
  end
end
