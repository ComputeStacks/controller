require "test_helper"
require "minitest/mock"

class LoadBalancerServices::DeployConfigServiceTest < ActiveSupport::TestCase
  # A queued Sidekiq job, as Sidekiq::Queue yields it.
  QueuedJob = Struct.new(:item, :args)

  setup do
    LoadBalancerWorkers::DeployConfigWorker.jobs.clear
  end

  def with_queue(jobs, &)
    Sidekiq::Queue.stub(:new, ->(_name) { jobs }, &)
  end

  test "a queued redeploy of every load balancer, queued as [nil], is not queued again" do
    queued = QueuedJob.new({"class" => "LoadBalancerWorkers::DeployConfigWorker"}, [nil])

    with_queue([queued]) do
      LoadBalancerServices::DeployConfigService.new.perform
    end

    assert_empty LoadBalancerWorkers::DeployConfigWorker.jobs
  end

  test "queues a redeploy of every load balancer when none is queued" do
    other = QueuedJob.new({"class" => "LoadBalancerWorkers::DeployConfigWorker"}, ["gid://cstacks/LoadBalancer/1"])

    with_queue([other]) do
      LoadBalancerServices::DeployConfigService.new.perform
    end

    assert_equal 1, LoadBalancerWorkers::DeployConfigWorker.jobs.size
    assert_equal [nil], LoadBalancerWorkers::DeployConfigWorker.jobs.first["args"]
  end
end
