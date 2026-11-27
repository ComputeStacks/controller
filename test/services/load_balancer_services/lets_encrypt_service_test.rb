require "test_helper"

class LoadBalancerServices::LetsEncryptServiceTest < ActiveSupport::TestCase
  test "links its event to the certificate before enqueuing" do
    lb = load_balancers(:default)
    cert = LetsEncrypt.create!(account: LetsEncryptAccount.create!)
    lb.update_columns(le: true, domain_valid: true, lets_encrypt_id: cert.id)

    Sidekiq::Worker.clear_all
    svc = LoadBalancerServices::LetsEncryptService.new(lb.reload)
    assert svc.perform
    assert_includes cert.event_logs.reload, svc.event
    job = LetsEncryptWorkers::GenerateCertWorker.jobs.last
    assert_equal [cert.id, svc.event.id], job["args"]
  end
end
