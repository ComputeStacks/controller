require 'test_helper'

class LoadBalancersControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin) # Admin user owns the registry.
  end

  test 'can create new load balancer' do
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
    crt_bundle = "#{cert.to_pem}#{key.to_pem}".gsub("\n", "\r\n")

    region = Region.first

    post "/admin/load_balancers", params: {
      load_balancer: {
        label: "newlbone",
        external_ips: "192.168.100.10",
        internal_ips: "192.168.100.10",
        public_ip: "192.168.100.10",
        domain: "c.app",
        region_id: region.id,
        direct_connect: true,
        le: false,
        shared_certificate: crt_bundle
      }
    }
    assert_response :redirect

    lb = LoadBalancer.find_by(label: 'newlbone')

    assert_not_nil lb
    assert_equal crt_bundle, lb.shared_certificate
    assert_equal "192.168.100.10", lb.public_ip

  end

  test 'can update certificate on existing load balancer' do
    lb = LoadBalancer.first

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
    crt_bundle = "#{cert.to_pem}#{key.to_pem}".gsub("\n", "\r\n")

    patch "/admin/load_balancers/#{lb.id}", params: {
      load_balancer: {
        shared_certificate: crt_bundle
      }
    }

    assert_response :redirect

    lb.reload

    assert_equal crt_bundle, lb.shared_certificate
  end

end
