require 'test_helper'

##
# Perform Domain Validation with IP and CAA Records
#
# Needs both ACME and PowerDNS containers to be running.
#
class Deployment::ContainerDomainTest < ActiveSupport::TestCase

  include AcmeTestContainerConcern # Only enable when you need to refresh VCR.
  include PdnsTestContainerConcern

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

    VCR.use_cassette('container_domains/validate_cert_1') do
      Sidekiq::Testing.inline! do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'cmptstks.com', # 192.168.173.10
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'cmptstks.com')
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

    VCR.use_cassette('container_domains/validate_cert_2') do
      Sidekiq::Testing.inline! do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'cmptstks.org', # 192.168.173.10
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'cmptstks.org')
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

    VCR.use_cassette('container_domains/validate_cert_3') do
      Sidekiq::Testing.inline! do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'cmptstks.net', # 192.168.173.10
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'cmptstks.net')
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    assert domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure failed events
    assert domain.event_logs.where(status: 'failed').exists?

    refute domain.le_ready

  end

  test 'valid root CAA, invalid subdomain CAA' do

    VCR.use_cassette('container_domains/validate_cert_4') do
      Sidekiq::Testing.inline! do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'test.cmptstks.us', # 192.168.173.10
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'test.cmptstks.us')
    refute domain.event_details.where(event_code: '510806d5621c97d5').exists?
    refute domain.event_details.where(event_code: 'afda9ae32934c1d8').exists?

    # EventLog created when invalid CAA record is found
    assert domain.event_details.where(event_code: '87744f149e2ed5ad').exists?

    # Ensure failed events
    assert domain.event_logs.where(status: 'failed').exists?

    refute domain.le_ready

  end

  test 'valid CAA on subdomain, invalid CAA on root' do

    VCR.use_cassette('container_domains/validate_cert_5') do
      Sidekiq::Testing.inline! do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'test.cmptstks.cc', # 192.168.173.10
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'test.cmptstks.cc')
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

    VCR.use_cassette('container_domains/validate_cert_6') do
      Sidekiq::Testing.inline! do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'www.usr.cloud', # 192.168.173.10
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'www.usr.cloud')
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

    VCR.use_cassette('container_domains/validate_cert_7') do
      Sidekiq::Testing.inline! do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'www.usr.ca', # 192.168.173.10
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end
    end

    domain = Deployment::ContainerDomain.find_by(domain: 'www.usr.ca')
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

      VCR.use_cassette('container_domains/validate_cert_8') do
        # Create the domain and enable Lets Encrypt
        Deployment::ContainerDomain.create!(
          domain: 'supercool33fakedomain22.net',
          le_enabled: true,
          enabled: true,
          ingress_rule: network_ingress_rules(:wordpress_web_http),
          user: users(:admin)
        )
      end

      domain = Deployment::ContainerDomain.find_by(domain: 'supercool33fakedomain22.net')
      refute domain.le_ready

      # Event should fail
      assert domain.event_logs.where(event_code: '971c02e9e85ad118', status: 'failed').exists?

      # We should see 3 failed attempts
      assert domain.event_details.where(event_code: 'afb5d727910b5954').count == 4

      # We should only have a single event
      assert_equal 1, domain.event_logs.where(event_code: '971c02e9e85ad118').count
    end
  end

end
