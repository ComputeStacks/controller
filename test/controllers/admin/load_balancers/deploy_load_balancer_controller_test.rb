require "test_helper"

class Admin::LoadBalancers::DeployLoadBalancerControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    LoadBalancerWorkers::ValidateDomainWorker.clear
  end

  # A new load balancer relying on automatic SSL has no certificate until its
  # domain validates, so Deploy must re-run validation rather than stop at the
  # missing certificate.
  test "invalid domain without a certificate triggers validation" do
    lb = load_balancers(:default)
    lb.update_columns(le: true, cert_encrypted: nil, domain_valid: false, lets_encrypt_id: nil)

    post "/admin/load_balancers/#{lb.id}/deploy_load_balancer"

    assert_redirected_to "/admin/load_balancers"
    assert_equal 1, LoadBalancerWorkers::ValidateDomainWorker.jobs.size
    assert_match(/triggering validation/, flash[:alert])
  end

  test "valid domain without a certificate reports the missing certificate" do
    lb = load_balancers(:default)
    lb.update_columns(le: true, cert_encrypted: nil, domain_valid: true, lets_encrypt_id: nil)

    post "/admin/load_balancers/#{lb.id}/deploy_load_balancer"

    assert_equal 0, LoadBalancerWorkers::ValidateDomainWorker.jobs.size
    assert_match(/Missing SSL Certificate/, flash[:alert])
  end
end
