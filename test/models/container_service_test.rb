require 'test_helper'

class ContainerServiceTest < ActiveSupport::TestCase

  test 'ensure correct network settings' do
    Deployment::ContainerService.all.each do |service|
      assert_not_empty service.ingress_rules
      if service.ingress_rules.where(external_access: true, proto: 'http').exists?
        assert_not_empty service.domains
      end
    end
  end

  test 'ensure correct calico policy' do
    Deployment::ContainerService.all.each do |service|
      policy = service.calico_policy
      assert_kind_of Hash, policy
      if service.ingress_rules.where(external_access: true).exists?
        assert_equal service.name, policy[:metadata][:name]
      end
    end
  end

  test 'can list all owned container services' do

    s = Deployment::ContainerService.first
    u = s.user

    assert_includes Deployment::ContainerService.find_all_for(u), s

  end

end
