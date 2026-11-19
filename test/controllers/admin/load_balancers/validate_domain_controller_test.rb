require "test_helper"

class Admin::LoadBalancers::ValidateDomainControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    LoadBalancerWorkers::ValidateDomainWorker.clear
  end

  # A load balancer whose validation job was lost has domain_valid at its
  # default true, so Deploy would not re-validate it; this button always does.
  test "queues domain validation regardless of the current verdict" do
    lb = load_balancers(:default)
    lb.update_columns(domain_valid: true, domain_valid_check: nil)

    post "/admin/load_balancers/#{lb.id}/validate_domain"

    assert_redirected_to "/admin/load_balancers"
    jobs = LoadBalancerWorkers::ValidateDomainWorker.jobs
    assert_equal [lb.id], jobs.map { |j| j["args"].first }
    assert_not_nil Audit.find_by(id: jobs.first["args"].last)
  end

  test "an unknown load balancer redirects with an error" do
    post "/admin/load_balancers/0/validate_domain"

    assert_redirected_to "/admin/load_balancers"
    assert_empty LoadBalancerWorkers::ValidateDomainWorker.jobs
  end
end
