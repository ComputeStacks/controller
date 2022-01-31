require 'test_helper'

##
# Perform Domain Validation with IP and CAA Records
#
# Needs both ACME and PowerDNS containers to be running.
#
class Deployment::ContainerDomainTest < ActiveSupport::TestCase

  include AcmeTestContainerConcern

  test 'can list all container domains' do

    d = Deployment::ContainerDomain.where.not(user: nil).first
    u = d.user

    assert_includes Deployment::ContainerDomain.find_all_for(u), d

  end

  test 'can list domain collaborators' do

    d = deployment_container_domains(:wordpress_default)
    u = users(:user)

    refute_includes Deployment::ContainerDomain.find_all_for(u), d

    d.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: u

    refute_includes Deployment::ContainerDomain.find_all_for(u), d

    d.deployment.deployment_collaborators.first.update active: true

    assert_includes Deployment::ContainerDomain.find_all_for(u), d

    d.deployment.deployment_collaborators.delete_all

  end

  test 'domain with valid ip and CAA' do

    Sidekiq::Testing.inline! do
      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'csdevserver.local', # 127.0.0.1
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'csdevserver.local')
    # These are created when A record is wrong
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    refute domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure no failed events
    refute domain.event_logs.where(status: 'failed').exists?

    assert domain.le_ready

  end

  test 'domain with valid ip and no CAA' do

    Sidekiq::Testing.inline! do
      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'cstacksorg.local', # 127.0.0.1
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'cstacksorg.local')
    # These are created when A record is wrong
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    refute domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure no failed events
    refute domain.event_logs.where(status: 'failed').exists?

    assert domain.le_ready

  end

  test 'domain with valid ip and invalid CAA' do

    Sidekiq::Testing.inline! do
      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'csnet.local', # 127.0.0.1
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'csnet.local')
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    assert domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure failed events
    assert domain.event_logs.where(status: 'failed').exists?

    refute domain.le_ready

  end

  test 'valid root CAA, invalid subdomain CAA' do

    Sidekiq::Testing.inline! do
      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'test.cstacksus.local', # 127.0.0.1
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'test.cstacksus.local')
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    assert domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure failed events
    assert domain.event_logs.where(status: 'failed').exists?

    refute domain.le_ready

  end

  test 'valid CAA on subdomain, invalid CAA on root' do

    Sidekiq::Testing.inline! do
      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'test.cstackscc.local', # 127.0.0.1
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'test.cstackscc.local')
    # These are created when A record is wrong
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    refute domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure no failed events
    refute domain.event_logs.where(status: 'failed').exists?

    assert domain.le_ready

  end

  test 'domain with cname and no caa' do

    Sidekiq::Testing.inline! do
      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'www.usrcloud.local', # 127.0.0.1
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'www.usrcloud.local')
    # These are created when A record is wrong
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    refute domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure no failed events
    refute domain.event_logs.where(status: 'failed').exists?

    assert domain.le_ready

  end

  test 'domain with cname and caa' do

    Sidekiq::Testing.inline! do
      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'www.usrca.local', # 127.0.0.1
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'www.usrca.local')
    # These are created when A record is wrong
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    refute domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure no failed events
    refute domain.event_logs.where(status: 'failed').exists?

    assert domain.le_ready

  end

  test 'domain that does not exist' do
    Sidekiq::Testing.inline! do

      # Create the domain and enable Lets Encrypt
      Deployment::ContainerDomain.create!(
        domain: 'supercool33fakedomain22.net',
        le_enabled: true,
        enabled: true,
        ingress_rule: network_ingress_rules(:wordpress_web_http),
        user: users(:admin)
      )

      domain = Deployment::ContainerDomain.find_by(domain: 'supercool33fakedomain22.net')
      refute domain.le_ready

      # Event should fail
      assert domain.event_logs.where(event_code: '971c02e9e85ad118', status: 'failed').exists?

      # We should see 3 failed attempts
      assert domain.event_details.where(event_code: 'afb5d727910b5954').count == 3

      # We should only have a single event
      assert_equal 1, domain.event_logs.where(event_code: '971c02e9e85ad118').count
    end
  end

end
