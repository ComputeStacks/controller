require 'test_helper'

class CertificatesControllerTest < ActionDispatch::IntegrationTest
  
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin) # Admin user owns the registry.
  end

  test 'can create new ssl certificate' do

    deployment = Deployment.first
    service = deployment.services.web_only.first

    key = OpenSSL::PKey::RSA.new(2048)
    public_key = key.public_key

    subject = "/C=BE/O=Test/OU=Test/CN=Test"

    cert = OpenSSL::X509::Certificate.new
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse(subject)
    cert.not_before = Time.now
    cert.not_after = Time.now + 365 * 24 * 60 * 60
    cert.public_key = public_key
    cert.serial = 0x0
    cert.version = 2

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.extensions = [
      ef.create_extension("basicConstraints","CA:TRUE", true),
      ef.create_extension("subjectKeyIdentifier", "hash")
    ]
    cert.add_extension ef.create_extension("authorityKeyIdentifier",
                                          "keyid:always,issuer:always")

    cert.sign key, OpenSSL::Digest::SHA256.new

    post "/deployments/#{deployment.token}/certificates", params: {
      deployment_ssl: {
        container_service_id: service.id,
        crt: cert.to_pem,
        pkey: key.to_pem
      }
    }

    assert_response :redirect

    # attempt to find this cert and verify

    created_crt = Deployment::Ssl.find_by(cert_serial: cert.serial.to_s)
    
    assert_not_nil created_crt

    assert_equal cert.to_pem, created_crt.crt
    assert_equal key.to_pem, created_crt.pkey
    

  end

end