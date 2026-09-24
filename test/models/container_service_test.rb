require "test_helper"

class ContainerServiceTest < ActiveSupport::TestCase
  test "ensure correct network settings" do
    Deployment::ContainerService.all.each do |service|
      assert_not_empty service.ingress_rules
      if service.ingress_rules.where(external_access: true, proto: "http").exists?
        assert_not_empty service.domains
      end
    end
  end

  test "ensure correct calico policy" do
    Deployment::ContainerService.all.each do |service|
      policy = service.calico_policy
      assert_kind_of Hash, policy
      if service.ingress_rules.where(external_access: true).exists?
        assert_equal service.name, policy[:metadata][:name]
      end
    end
  end

  test "can list all owned container services" do
    s = Deployment::ContainerService.first
    u = s.user

    assert_includes Deployment::ContainerService.find_all_for(u), s
  end

  # --- shm_size / ShmSizeValidator ---

  test "shm_size of 0 is valid (uses image default)" do
    service = deployment_container_services(:mysql)
    service.shm_size = 0
    assert service.valid?, service.errors.full_messages.to_sentence
  end

  test "negative shm_size is invalid" do
    service = deployment_container_services(:mysql)
    service.shm_size = -1
    refute service.valid?
    assert_includes service.errors[:shm_size], "must be greater than or equal to 0"
  end

  test "shm_size within the memory limit is valid" do
    service = deployment_container_services(:mysql) # memory: 1024 MB
    service.shm_size = 256 * 1_048_576
    assert service.valid?, service.errors.full_messages.to_sentence
  end

  test "shm_size above the memory limit is invalid" do
    service = deployment_container_services(:mysql) # memory: 1024 MB
    service.shm_size = (service.memory + 1) * 1_048_576
    refute service.valid?
    assert_includes service.errors[:shm_size], "cannot exceed the service's memory limit (#{service.memory} MB)"
  end

  test "shm_size cap is skipped when memory is unknown" do
    service = deployment_container_services(:mysql)
    service.memory = nil
    service.shm_size = 999 * 1_048_576
    assert service.valid?, service.errors.full_messages.to_sentence
  end

  test "shm_size_mb converts to and from bytes" do
    service = deployment_container_services(:mysql)
    service.shm_size_mb = 256
    assert_equal 256 * 1_048_576, service.shm_size
    assert_equal 256, service.shm_size_mb
  end

  test "shm_size_mb of 0 clears to the image default" do
    service = deployment_container_services(:mysql)
    service.shm_size = 128 * 1_048_576
    service.shm_size_mb = 0
    assert_equal 0, service.shm_size
  end

  test "assigning the same shm_size_mb preserves exact bytes" do
    service = deployment_container_services(:mysql)
    service.update_column(:shm_size, 100_000_000) # ~95.37 MB, not a whole MB
    assert_equal 95, service.shm_size_mb
    service.shm_size_mb = 95 # same rounded MB the getter reports
    assert_equal 100_000_000, service.shm_size # unchanged, no re-round
  end

  test "unrelated updates are not blocked by an over-cap shm_size" do
    service = deployment_container_services(:mysql) # memory: 1024 MB
    # Simulate a value set via console before the validator existed, over the (future) cap.
    service.update_column(:shm_size, (service.memory + 512) * 1_048_576)
    # A memory resize must still persist because shm_size isn't changing (validator skips).
    assert service.update(memory: 256), service.errors.full_messages.to_sentence
    assert_equal 256, service.reload.memory
  end
end
