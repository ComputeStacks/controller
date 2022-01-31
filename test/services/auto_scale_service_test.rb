require 'test_helper'

class AutoScaleServiceTest < ActiveSupport::TestCase

  test 'can auto-scale by resize' do
    service = deployment_container_services(:mysql)

    ##
    # By Memory
    orig_mem = service.containers.first.memory
    s = ContainerServices::AutoScaleService.new service, 'memory'
    assert s.perform
    assert service.containers.first.memory > orig_mem

    ##
    # By CPU
    orig_cpu = service.containers.first.cpu
    s = ContainerServices::AutoScaleService.new service, 'cpu'
    assert s.perform
    assert service.containers.first.cpu > orig_cpu
  end

  test 'can auto-scale by scale' do
    service = deployment_container_services(:wordpress)
    orig_count = service.containers.count
    s = ContainerServices::AutoScaleService.new service, 'memory'
    assert s.perform
    assert_equal orig_count + 1, service.containers.count
  end

  test 'can not exceed max price' do
    service = deployment_container_services(:nginx)
    s = ContainerServices::AutoScaleService.new service, 'memory'
    refute s.perform
    assert_equal 'cancelled', s.event.status
    assert s.event.event_details.where(event_code: 'b192b7fcb4e94b0c').exists?
  end

end
