require 'test_helper'

##
# ACME integration testing for ContainerDomains
#
# Resources:
# * [ACME Dev Server](https://github.com/letsencrypt/pebble#skipping-validation)
# * [LetsEncrypt Staging Server](https://letsencrypt.org/docs/staging-environment/)
#
class LetsEncryptFlowTest < ActionDispatch::IntegrationTest

  test 'can enable lets encrypt on a domain' do
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
    refute domain.nil?
    refute_nil domain.le_ready_checked

    assert domain.le_ready
    refute_nil domain.lets_encrypt

    assert domain.lets_encrypt.expected_domains.include?(domain.domain)
    assert_equal domain.user, domain.lets_encrypt.user

    Sidekiq::Testing.inline! do
      # This is how it's called from clockwork
      LetsEncryptWorkers::GenerateCertWorker.perform_async nil
    end

    domain.reload
    lets_encrypt = domain.lets_encrypt

    assert lets_encrypt.names.include?(domain.domain)
    refute_nil lets_encrypt.expires_at
    refute_nil lets_encrypt.last_generated_at

    # Verify generated cert belongs to the private key
    cert = OpenSSL::X509::Certificate.new(lets_encrypt.crt)
    assert_kind_of OpenSSL::X509::Certificate, cert

    assert cert.check_private_key(lets_encrypt.private_key)

    refute lets_encrypt.can_renew?

    # Ensure when we add a new domain, we can re-generate our lets_encrypt certificate
    new_domain = Deployment::ContainerDomain.create!(
      domain: 'foobardev.net',
      le_enabled: true,
      le_ready: true,
      le_ready_checked: Time.now,
      lets_encrypt: lets_encrypt,
      ingress_rule: network_ingress_rules(:wordpress_web_http),
      user: users(:admin)
    )

    lets_encrypt.reload
    assert_includes lets_encrypt.expected_domains, new_domain.domain

    assert lets_encrypt.can_renew?

    # Ensure that when we disable LE, the cert connection is removed
    new_domain.update_attribute :le_enabled, false
    new_domain.reload
    lets_encrypt.reload
    assert_nil new_domain.lets_encrypt
    refute_includes lets_encrypt.expected_domains, new_domain.domain

    # Ensure that when we lose validation, the cert connection is removed
    domain.update_attribute :le_ready, false
    domain.reload
    lets_encrypt.reload
    assert_nil new_domain.lets_encrypt
    refute_includes lets_encrypt.expected_domains, domain.domain

    # Ensure that now that our cert is empty, it should be deleted on the next validation run
    le_id = lets_encrypt.id
    Sidekiq::Testing.inline! do
      LetsEncryptWorkers::GenerateCertWorker.perform_async le_id, nil
    end

    assert_nil LetsEncrypt.find_by(id: le_id)
  end

end
