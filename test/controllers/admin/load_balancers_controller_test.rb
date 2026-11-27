require "test_helper"

class LoadBalancersControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin) # Admin user owns the registry.
  end

  test "the list shows which domains were never checked" do
    lb = load_balancers(:default)
    lb.update_columns(domain_valid: true, domain_valid_check: nil)
    get "/admin/load_balancers"
    assert_response :success
    assert_select "span.label-warning", "Never checked"

    lb.update_columns(domain_valid: false, domain_valid_check: Time.now)
    get "/admin/load_balancers"
    assert_select "span.label-danger", "Invalid"
  end

  test "the list shows certificate expiry and renewal backoff" do
    lb = load_balancers(:default)
    cert = LetsEncrypt.create!(user_id: nil, account: LetsEncryptAccount.create!)
    lb.update_columns(le: true, lets_encrypt_id: cert.id)
    get "/admin/load_balancers"
    assert_select "span.label-warning", "Not issued"

    cert.update_columns(expires_at: 5.days.from_now, failure_count: 3, next_attempt_at: 2.hours.from_now)
    get "/admin/load_balancers"
    assert_select "span.label-danger", "5d left"
    assert_select "small.text-danger", /3 failed attempts, retry in about 2 hours/

    cert.update_columns(expires_at: 60.days.from_now, failure_count: 0, next_attempt_at: nil)
    get "/admin/load_balancers"
    assert_select "span.label-success", "60d left"
    assert_select "small.text-danger", false
  end

  test "can create new load balancer" do
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
      ef.create_extension("basicConstraints", "CA:TRUE", true),
      ef.create_extension("subjectKeyIdentifier", "hash")
    ]
    cert.add_extension ef.create_extension("authorityKeyIdentifier",
      "keyid:always,issuer:always")

    cert.sign key, OpenSSL::Digest.new("SHA256")
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

    lb = LoadBalancer.find_by(label: "newlbone")

    assert_not_nil lb
    assert_equal crt_bundle, lb.shared_certificate
    assert_equal "192.168.100.10", lb.public_ip
  end

  test "can update certificate on existing load balancer" do
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
      ef.create_extension("basicConstraints", "CA:TRUE", true),
      ef.create_extension("subjectKeyIdentifier", "hash")
    ]
    cert.add_extension ef.create_extension("authorityKeyIdentifier",
      "keyid:always,issuer:always")

    cert.sign key, OpenSSL::Digest.new("SHA256")
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
