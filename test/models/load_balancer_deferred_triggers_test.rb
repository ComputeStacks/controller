require "test_helper"
require "minitest/mock"

##
# LoadBalancer#trigger_domain_validation and #trigger_le_generation decide at save
# time but act only after every open transaction commits. `rake bootstrap:apply`
# creates load balancers inside one long transaction; a ValidateDomainWorker
# pushed before that commit could run against a row it can't see yet and exit
# silently, leaving domain_valid_check nil forever.
#
# NB the transactional-fixture transaction is non-joinable, so outside an
# explicit transaction the deferred block runs inline, as it does in production.
class LoadBalancerDeferredTriggersTest < ActiveSupport::TestCase
  setup do
    LoadBalancerWorkers::ValidateDomainWorker.clear
  end

  def build_lb(**attrs)
    LoadBalancer.new(
      region: Region.first,
      public_ip: "127.0.0.1",
      ext_ip: ["127.0.0.1"],
      domain: "deferred.example.com",
      **attrs
    )
  end

  def validate_jobs
    LoadBalancerWorkers::ValidateDomainWorker.jobs
  end

  test "domain validation is queued immediately when no transaction is open" do
    lb = build_lb
    lb.save!
    assert_equal [lb.id], validate_jobs.map { |j| j["args"].first }
  end

  test "domain validation is queued only once the enclosing transaction commits" do
    lb = nil
    ActiveRecord::Base.transaction do
      lb = build_lb
      lb.save!
      assert_empty validate_jobs, "job pushed before the row was committed"
    end
    assert_equal [lb.id], validate_jobs.map { |j| j["args"].first }
  end

  test "domain validation is queued after a savepoint inside an outer transaction commits" do
    lb = nil
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.transaction(requires_new: true) do
        lb = build_lb
        lb.save!
      end
      assert_empty validate_jobs, "job pushed when only the savepoint was released"
    end
    assert_equal [lb.id], validate_jobs.map { |j| j["args"].first }
  end

  test "a rolled-back transaction queues no domain validation" do
    ActiveRecord::Base.transaction do
      build_lb.save!
      raise ActiveRecord::Rollback
    end
    assert_empty validate_jobs
  end

  test "an unchanged domain queues nothing" do
    lb = build_lb
    lb.save!
    LoadBalancerWorkers::ValidateDomainWorker.clear
    lb.update!(label: "renamed")
    assert_empty validate_jobs
  end

  test "a savepoint rolled back inside a committed transaction queues nothing" do
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.transaction(requires_new: true) do
        build_lb.save!
        raise ActiveRecord::Rollback
      end
    end
    assert_empty validate_jobs
  end

  test "the audit current at save time is the one handed to the job" do
    audit = Audit.create!(event: "updated", rel_model: "LoadBalancer")
    lb = nil
    ActiveRecord::Base.transaction do
      lb = build_lb
      lb.current_audit = audit
      lb.save!
      lb.current_audit = nil
    end
    assert_equal [[lb.id, audit.id]], validate_jobs.map { |j| j["args"] }
  end

  test "a failed push after commit is alerted, not raised into the caller" do
    alerts = []
    alert = ->(e, code) { alerts << [e.message, code]; Struct.new(:perform).new(nil) }
    lb = nil
    LoadBalancerWorkers::ValidateDomainWorker.stub(:perform_async, ->(*) { raise "redis down" }) do
      ExceptionAlertService.stub(:new, alert) do
        ActiveRecord::Base.transaction do
          lb = build_lb
          lb.save!
        end
      end
    end
    assert lb.persisted?
    assert_equal ["redis down"], alerts.map(&:first)
  end

  def stub_le_service
    calls = []
    fake = ->(lb, _audit) { Struct.new(:lb) { define_method(:perform) { calls << lb.id } }.new(lb) }
    LoadBalancerServices::LetsEncryptService.stub(:new, fake) { yield calls }
  end

  test "skip_validation suppresses both triggers" do
    lb = build_lb
    lb.save!
    LoadBalancerWorkers::ValidateDomainWorker.clear
    stub_le_service do |calls|
      lb.skip_validation = true
      lb.update!(le: true, domain: "skipped.example.com")
      assert_empty calls
    end
    assert_empty validate_jobs
  end

  test "enabling lets encrypt runs the service only after commit, and not at all on rollback" do
    lb = build_lb
    lb.save!
    stub_le_service do |calls|
      ActiveRecord::Base.transaction do
        lb.update!(le: true)
        raise ActiveRecord::Rollback
      end
      assert_empty calls

      lb.reload
      ActiveRecord::Base.transaction do
        lb.update!(le: true)
        assert_empty calls, "LetsEncryptService ran inside the transaction"
      end
      assert_equal [lb.id], calls
    end
  end

  # ValidateDomainWorker runs LetsEncryptService itself once the domain
  # validates; a second, direct run would order a duplicate certificate.
  test "a new domain with lets encrypt leaves certificate generation to the validation worker" do
    stub_le_service do |calls|
      lb = build_lb(le: true)
      lb.save!
      assert_empty calls
      assert_equal [lb.id], validate_jobs.map { |j| j["args"].first }
    end
  end

  test "disabling lets encrypt alongside a domain change still runs the service" do
    lb = build_lb(le: true)
    lb.save!
    stub_le_service do |calls|
      lb.update!(le: false, domain: "moved.example.com")
      assert_equal [lb.id], calls
    end
  end
end
