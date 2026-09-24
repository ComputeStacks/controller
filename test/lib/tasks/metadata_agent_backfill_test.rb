require "test_helper"
require "minitest/mock"
require "rake"

##
# metadata:agent_backfill provisions every project's tenant on its node agent. Two things an
# automated caller depends on: it can be pointed at one node instead of the whole fleet, and a
# project that failed makes the run fail. It used to print [fail] and still exit 0, so the
# provisioner recorded a successful seed while the tenant was never provisioned.
class MetadataAgentBackfillTest < ActiveSupport::TestCase
  class FakeAgentClient
    attr_reader :provisioned

    def initialize(raise_with: nil)
      @raise_with = raise_with
      @provisioned = 0
    end

    def provision_tenant!
      raise @raise_with if @raise_with
      @provisioned += 1
      true
    end
  end

  class NoopService
    def initialize(*) = nil

    def perform = true
  end

  # Guard on the task being defined, not on a per-class flag: Rails.application.load_tasks
  # APPENDS the task body as another action every time it runs, so a second class loading
  # tasks in the same process would make this task's body execute twice.
  def self.load_tasks_once
    Rails.application.load_tasks unless Rake::Task.task_defined?("metadata:agent_backfill")
  end

  setup do
    self.class.load_tasks_once
    @task = Rake::Task["metadata:agent_backfill"]
    @task.reenable
    @node = nodes(:testone)
    @client = FakeAgentClient.new
  end

  teardown do
    ENV.delete("NODE_ID")
    ENV.delete("NODE")
  end

  def run_task
    out = nil
    with_stubs { out = capture_io { @task.invoke }.first }
    out
  end

  # capture_io cannot be used when the task exits: the exception unwinds past it.
  def run_failing_task
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    error = assert_raises(SystemExit) { with_stubs { @task.invoke } }
    [captured.string, error]
  ensure
    $stdout = original
  end

  def with_stubs
    Agent::Client.stub(:new, ->(*, **) { @client }) do
      ProjectServices::StoreMetadata.stub(:new, ->(*) { NoopService.new }) do
        ProjectServices::MetadataSshKeys.stub(:new, ->(*) { NoopService.new }) do
          SftpServices::MetadataSshHostKeys.stub(:new, ->(*) { NoopService.new }) do
            yield
          end
        end
      end
    end
  end

  test "processes every project by default" do
    out = run_task
    assert_equal Deployment.count, @client.provisioned
    assert_match(/ok=#{Deployment.count} skipped=0 failed=0/, out)
  end

  test "NODE_ID limits the pass to the projects in that node's region" do
    other = second_region_node
    ENV["NODE_ID"] = other.id.to_s

    out = run_task

    # The new region has no projects, so nothing is provisioned — the fleet's existing
    # projects are left completely alone.
    assert_equal 0, @client.provisioned
    assert_match(/Scoped to node #{other.id}/, out)
    assert_match(/ok=0 skipped=0 failed=0/, out)
  end

  test "NODE selects by hostname and still covers that node's region" do
    ENV["NODE"] = @node.hostname
    out = run_task
    assert_equal Deployment.count, @client.provisioned
    assert_match(/Scoped to node #{@node.id}/, out)
  end

  test "an unknown NODE exits non-zero rather than silently running the whole fleet" do
    ENV["NODE"] = "does-not-exist"
    out, error = run_failing_task
    assert_equal 1, error.status
    assert_match(/no node matching NODE=does-not-exist/, out)
    assert_equal 0, @client.provisioned
  end

  test "a failed project makes the run exit non-zero" do
    @client = FakeAgentClient.new(raise_with: RuntimeError.new("agent refused"))
    out, error = run_failing_task
    assert_equal 1, error.status
    assert_match(/\[fail\] project /, out)
    assert_match(/metadata:agent_backfill FAILED/, out)
  end

  test "a skipped project is not a failure" do
    # NotReady means "the node is not up yet, re-run later", which is the resumable path
    # the task is built around — it must not turn a fresh install into a failed seed.
    @client = FakeAgentClient.new(raise_with: Agent::Client::NotReady.new("no online node"))
    out = run_task
    assert_match(/skipped=#{Deployment.count}/, out)
    assert_match(/failed=0/, out)
  end

  private

  def second_region_node
    location = Location.create!(name: "second-location")
    region = Region.create!(name: "second-region", location: location)
    Node.create!(
      label: "second-node",
      hostname: "second-node",
      primary_ip: "10.77.0.2",
      public_ip: "10.77.0.2",
      region: region,
      active: true
    )
  end
end
