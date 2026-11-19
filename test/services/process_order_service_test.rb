require "test_helper"
require "minitest/mock"

##
# `finalize!` runs AFTER every container, subscription and volume in the order is already
# built — so anything it records in `errors` fails an order whose resources exist, and
# fail_process! then releases the project's private network. Only genuinely unrecoverable
# work belongs in `errors` here; self-healing conditions belong on the event.
class ProcessOrderServiceTest < ActiveSupport::TestCase
  # Stand-in for the provisioners finalize! calls. Reports success and no errors, so the
  # only thing under test is the agent-tenant branch.
  class FakeProvisioner
    attr_accessor :volume_clones

    def perform = true

    def errors = []
  end

  setup do
    @project = deployments(:project_test)
    @event = EventLog.create!(
      locale: "order.provision",
      event_code: "0a3af01a3384fa10",
      audit: Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "created"),
      status: "pending"
    )
    @service = ProcessOrderService.new(Order.new)
    @service.project = @project
    @service.region = regions(:regionone)
    @service.event = @event
  end

  # Replace the downstream provisioners with successful fakes so the assertion is about
  # the agent-tenant branch alone, then run the real finalize!.
  def finalize_with_agent(agent_new)
    fake = FakeProvisioner.new
    Agent::Client.stub(:new, agent_new) do
      ProvisionServices::SftpProvisioner.stub(:new, ->(*) { fake }) do
        ProjectServices::MetadataSshKeys.stub(:new, ->(*) { fake }) do
          DeployServices::DeployProjectService.stub(:new, ->(*) { fake }) do
            @service.send(:finalize!)
          end
        end
      end
    end
  end

  test "an agent that is not ready does not fail an order whose resources are already built" do
    not_ready = ->(*, **) { raise Agent::Client::NotReady, "node 1 has no agent_token" }

    assert finalize_with_agent(not_ready), "finalize! must not fail on a NotReady agent"
    assert_empty @service.errors

    detail = @event.event_details.find_by(event_code: "7239068cdeb3b779")
    refute_nil detail, "the skipped tenant provisioning must be recorded on the event"
    assert_match "node 1 has no agent_token", detail.data
  end

  test "the tenant is provisioned with the project's metadata bearer" do
    provisioned = []
    client = Object.new
    client.define_singleton_method(:provision_tenant!) { provisioned << true }

    assert finalize_with_agent(->(*, **) { client })
    assert_equal [true], provisioned
    assert @project.reload.consul_auth_key.present?, "expected the metadata bearer to be minted"
  end

  # --- the order's containers must have a network and IP before anything is built --------
  #
  # 2026-10-20: two concurrent orders claimed the same network row, and the loser's order
  # completed with containers that had no network and no IP. This one deliberately IS an
  # `errors` entry: building a container with no IP can only fail.

  class RecordingDeployer
    attr_accessor :volume_clones
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def perform
      @calls += 1
      true
    end

    def errors = []
  end

  # Answers from a per-container script of results (last one repeats); :ready otherwise.
  class ScriptedEnsure
    attr_reader :reason

    def initialize(container, script, log)
      @container = container
      @script = script
      @log = log
    end

    def perform
      @log << @container
      queue = @script[@container]
      return :ready if queue.nil?
      status = (queue.length > 1) ? queue.shift : queue.first
      @reason = "#{@container.name} is broken" unless status == :ready
      status
    end
  end

  def finalize_with_network_check(ensure_new: nil)
    fake = FakeProvisioner.new
    deployer = RecordingDeployer.new
    client = Object.new
    client.define_singleton_method(:provision_tenant!) { true }
    sleeps = []
    run = -> do
      Agent::Client.stub(:new, ->(*, **) { client }) do
        ProvisionServices::SftpProvisioner.stub(:new, ->(*) { fake }) do
          ProjectServices::MetadataSshKeys.stub(:new, ->(*) { fake }) do
            DeployServices::DeployProjectService.stub(:new, ->(*) { deployer }) do
              @service.stub(:sleep, ->(s) { sleeps << s }) do
                @service.send(:finalize!)
              end
            end
          end
        end
      end
    end
    ok = if ensure_new
      NetworkServices::EnsureContainerNetworkService.stub(:new, ensure_new) { run.call }
    else
      run.call
    end
    [ok, deployer, sleeps]
  end

  def scripted(script)
    log = []
    [->(container, _event) { ScriptedEnsure.new(container, script, log) }, log]
  end

  test "a container this order created with no IP is repaired before it is deployed" do
    network = networks(:net_gen_0)
    Network.where(deployment_id: @project.id).update_all(deployment_id: nil)
    network.update_columns(deployment_id: @project.id, active: true)
    container = deployment_containers(:wordpress_1)
    container.ip_address.destroy!
    @service.result[:containers] << container.reload

    ok, deployer, = finalize_with_network_check

    assert ok, @service.errors.inspect
    assert_empty @service.errors
    assert_equal network.id, container.reload.ip_address&.network_id
    assert_equal 1, deployer.calls, "the order must still be deployed"
  end

  test "a container that cannot be repaired fails the order before any build is queued" do
    container = deployment_containers(:wordpress_1)
    @service.result[:containers] << container
    ensure_new, log = scripted(container => [:retry])

    ok, deployer, sleeps = finalize_with_network_check(ensure_new: ensure_new)

    refute ok
    assert_equal ["#{container.name} is broken"], @service.errors
    assert_equal 0, deployer.calls, "nothing may be deployed for a container with no network"
    assert_equal 3, log.count(container)
    assert_equal [2, 2], sleeps
  end

  test "a failed container is not asked again" do
    container = deployment_containers(:wordpress_1)
    @service.result[:containers] << container
    ensure_new, log = scripted(container => [:failed])

    ok, deployer, sleeps = finalize_with_network_check(ensure_new: ensure_new)

    refute ok
    assert_equal 1, log.count(container)
    assert_empty sleeps
    assert_equal 0, deployer.calls
  end

  test "retries stop once the container is ready" do
    container = deployment_containers(:wordpress_1)
    @service.result[:containers] << container
    ensure_new, log = scripted(container => [:retry, :ready])

    ok, deployer, sleeps = finalize_with_network_check(ensure_new: ensure_new)

    assert ok, @service.errors.inspect
    assert_empty @service.errors
    assert_equal 2, log.count(container)
    assert_equal [2], sleeps
    assert_equal 1, deployer.calls
  end

  test "the project's pre-existing containers are not checked" do
    old_sftp = deployment_sftp(:project_test_testone)
    old = deployment_containers(:mysql_1)
    old.ip_address.destroy!
    new_container = deployment_containers(:wordpress_1)
    @service.result[:containers] << new_container
    ensure_new, log = scripted(old => [:failed])

    ok, deployer, = finalize_with_network_check(ensure_new: ensure_new)

    assert ok, @service.errors.inspect
    refute_includes log, old
    assert_includes log, new_container
    refute_includes log, old_sftp, "pre-existing SFTP containers are not checked"
    assert_equal 1, deployer.calls
  end

  test "an SFTP container created by this order is checked" do
    sftp = deployment_sftp(:project_test_testone)
    sftp.update_column :created_at, Time.current
    ensure_new, log = scripted(sftp => [:ready])

    ok, = finalize_with_network_check(ensure_new: ensure_new)

    assert ok, @service.errors.inspect
    assert_includes log, sftp
  end

  # --- releasing the project's private network on failure -------------------------------
  #
  # Detaching the row is not a release. The row stays `active`, and `active` is the only
  # thing keeping it out of GenerateProjectNetworkService's allocation pool -- so a row
  # detached but left active is correctly parked, and one whose docker network is gone must
  # be handed back. TrashBridgeNetworkService is what draws that line; fail_process! must
  # actually call it, and must never raise while doing so.

  test "releasing the network detaches the row and trashes it on the node" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project

    Docker::Network.stub(:get, ->(*) { raise Docker::Error::NotFoundError }) do
      @service.send(:release_network!)
    end

    network.reload
    assert_nil network.deployment_id
    assert_equal false, network.active, "a network confirmed off the node returns to the pool"
  end

  # The other half: a node that cannot confirm the removal leaves the row active, so it is
  # not handed to the next project while a copy still holds its subnet.
  test "releasing the network leaves the row parked when the node cannot confirm" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project

    Docker::Network.stub(:get, ->(*) { raise "connection refused" }) do
      @service.send(:release_network!)
    end

    network.reload
    assert_nil network.deployment_id
    assert_equal true, network.active
  end

  # fail_process! runs on the failure path, including from perform's ensure. A raise here
  # would replace the real failure with this one.
  test "releasing the network never raises" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project

    NetworkServices::TrashBridgeNetworkService.stub(:new, ->(*) { raise "boom" }) do
      assert_nothing_raised { @service.send(:release_network!) }
    end

    assert_nil network.reload.deployment_id
  end

  test "releasing the network is a no-op when the project has none" do
    Network.where(deployment_id: @project.id).update_all(deployment_id: nil)
    @project.reload

    assert_nothing_raised { @service.send(:release_network!) }
  end

  # Order stand-in: ProcessOrderService#initialize reads these three, and fail_process! calls
  # fail!. An unsaved Order can't do the last one.
  class FakeOrder
    attr_reader :failed
    attr_accessor :deployment, :order_data

    def current_event = nil

    def data = {}

    def fail!
      @failed = true
    end
  end

  # Records the row's state at the moment TrashBridgeNetworkService is handed it.
  class RecordingTrasher
    class << self
      attr_accessor :seen, :calls
    end

    def initialize(network)
      self.class.calls = self.class.calls.to_i + 1
      self.class.seen = [network.active, network.deployment_id]
    end

    def perform
      false
    end
  end

  # The wiring, not just the method: deleting the call from fail_process! must fail something.
  test "failing an order releases its private network" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project
    service = ProcessOrderService.new(FakeOrder.new)
    service.project = @project
    service.event = @event
    service.errors = []

    Docker::Network.stub(:get, ->(*) { raise Docker::Error::NotFoundError }) do
      service.send(:fail_process!, "boom")
    end

    network.reload
    assert_nil network.deployment_id
    assert_equal false, network.active
  end

  # The allocation pool is "inactive AND no project". A network whose create failed is already
  # inactive, so detaching it first would put it in the pool before anything had established
  # that it is off the node -- the same ordering inversion this whole change exists to fix.
  test "an unconfirmed network is marked active before it is detached" do
    network = networks(:net_gen_1)
    network.update! active: false, deployment: @project
    RecordingTrasher.seen = nil
    RecordingTrasher.calls = 0

    NetworkServices::TrashBridgeNetworkService.stub(:new, ->(net) { RecordingTrasher.new(net) }) do
      @service.send(:release_network!)
    end

    assert_equal 1, RecordingTrasher.calls
    assert_equal [true, nil], RecordingTrasher.seen,
      "the row must be parked, not pooled, until the node confirms the network is gone"
    assert_equal true, network.reload.active
  end

  # Production, 2026-09-04: a SECOND order against a project provisioned the day before failed,
  # and six seconds later that project's private network row was detached -- while its three
  # containers and its SFTP container carried on running. The project then had no network
  # record at all, and PrivateNetCleanupWorker began considering a live customer's network for
  # deletion every ten minutes, held off only by its addresses.
  #
  # An order against an existing project never allocates a network in the first place --
  # GenerateProjectNetworkService returns early with "Project network already configured" --
  # so there is nothing for the failure path to release.
  test "an order against an existing project does not release the network it came in with" do
    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project

    order = FakeOrder.new
    order.deployment = @project
    service = ProcessOrderService.new(order)
    service.project = @project
    service.event = @event
    service.errors = []

    service.send(:release_network!)

    network.reload
    assert_equal @project.id, network.deployment_id, "a running project must keep its network"
    assert_equal true, network.active
  end

  # ... but a network THIS order allocated is still released, whether the project is new or
  # was created earlier without one.
  test "a network this order allocated is released even when the project already existed" do
    Network.where(deployment_id: @project.id).update_all(deployment_id: nil)
    @project.reload

    order = FakeOrder.new
    order.deployment = @project # existed, but carried no network
    service = ProcessOrderService.new(order)
    service.project = @project
    service.event = @event
    service.errors = []

    network = networks(:net_gen_1)
    network.update! active: true, deployment: @project
    # Deliberately NOT reloading the project: production does not. The has_one was read as nil
    # when the service was built, and binding the row does not update that cached side.

    Docker::Network.stub(:get, ->(*) { raise Docker::Error::NotFoundError }) do
      service.send(:release_network!)
    end

    assert_nil network.reload.deployment_id
  end

  # The sequence production actually runs, which a `project.reload` in a test would hide.
  #
  # GenerateProjectNetworkService#perform reads `project.private_network` to decide whether to
  # allocate at all -- caching nil on the project -- and then binds a row by setting the
  # Network's belongs_to. There is no inverse_of, so the project's cached side still answers
  # nil afterwards. Reading the association at failure time therefore finds nothing and
  # releases nothing, on every failure before finalize! (which happens to reload).
  test "a network allocated after the project's association was cached is still released" do
    Network.where(deployment_id: @project.id).update_all(deployment_id: nil)
    @project.reload

    order = FakeOrder.new
    order.deployment = @project
    service = ProcessOrderService.new(order)
    service.project = @project
    service.event = @event
    service.errors = []

    # This is the read GenerateProjectNetworkService makes, and it caches nil.
    assert_nil @project.private_network

    network = networks(:net_gen_1)
    network.update! active: false, deployment: @project
    assert_nil @project.private_network, "the cached association still answers nil -- the bug"

    Docker::Network.stub(:get, ->(*) { raise Docker::Error::NotFoundError }) do
      service.send(:release_network!)
    end

    network.reload
    assert_nil network.deployment_id, "the range this order allocated must not stay bound to a failed project"
    assert_equal false, network.active
  end

  # --- the provisioning loop: dependencies first, stop at the first failure ---------------
  #
  # Production, 2026-09-04: orders for [wordpress, mariadb, redis] built WordPress and Redis,
  # then failed on the database, leaving sites that could never work. The loop also skipped
  # every other product on a pass (it deleted from the array it was iterating).

  # Stands in for ContainerServiceOrderService. The test's script, keyed by product label,
  # says what each product does: :ok, :fail (false, no errors), :error (an error message),
  # or :defer (volumes not ready yet) followed by what it does once ready.
  class ScriptedJob
    attr_accessor :provision_state
    attr_reader :errors, :result

    def initialize(product, script, log)
      @product = product
      @script = script
      @log = log
      @errors = []
      @result = {containers: [], subscriptions: [], load_balancers: [], volumes: [], volume_map: [], volume_clones: []}
    end

    def ready_to_provision?
      queue = @script[@product[:label]]
      return true unless queue&.first == :defer
      queue.shift
      false
    end

    def perform
      @log << @product[:label]
      case Array(@script[@product[:label]]).first
      when :fail then false
      when :error
        @errors << "#{@product[:label]} broke"
        false
      else true
      end
    end
  end

  def create_order(labels)
    raw_order = labels.map do |label|
      {product_type: "container", image_variant_id: container_image_image_variants(label).id, label: label.to_s}
    end
    Order.create!(
      user: users(:admin),
      deployment: @project,
      location: regions(:regionone).location,
      status: "pending",
      order_data: {"project" => {"id" => @project.id}, "region_id" => regions(:regionone).id, "raw_order" => raw_order}
    )
  end

  # Runs the real perform with everything around the loop stubbed out.
  def perform_order(order, script = {})
    log = []
    order.current_event = @event
    service = ProcessOrderService.new(order)
    service.region.stub(:has_clustered_networking?, true) do
      OrderServices::ContainerServiceOrderService.stub(:new, ->(_o, _e, _p, product) { ScriptedJob.new(product, script, log) }) do
        service.stub(:valid?, true) do
          service.stub(:within_quota?, true) do
            service.stub(:init_project!, true) do
              service.stub(:finalize!, true) do
                service.stub(:sleep, nil) do
                  [service.perform, service, log]
                end
              end
            end
          end
        end
      end
    end
  end

  test "dependencies are provisioned first, and every product once, in order" do
    order = create_order(%i[wordpress_default mariadb_default pma_default])

    ok, service, log = perform_order(order)

    assert ok, service.errors.inspect
    assert_equal %w[mariadb_default wordpress_default pma_default], log
    assert order.reload.success?
  end

  test "a failed dependency stops the order before anything else is built" do
    order = create_order(%i[wordpress_default mariadb_default pma_default])

    ok, service, log = perform_order(order, {"mariadb_default" => [:error]})

    refute ok
    assert_equal %w[mariadb_default], log
    assert_equal ["mariadb_default broke"], service.errors
    assert order.reload.failed?
  end

  test "a product that fails without errors still stops the order" do
    order = create_order(%i[pma_default elasticsearch_default nginx_default])

    ok, service, log = perform_order(order, {"elasticsearch_default" => [:fail]})

    refute ok
    assert_equal %w[pma_default elasticsearch_default], log
    assert_equal ["Failed to build product"], service.errors
    assert_equal "Failed to build product", order.reload.order_data["failure_reason"]
  end

  test "a product waiting on volumes is retried on the next pass and is not a failure" do
    order = create_order(%i[pma_default elasticsearch_default nginx_default])

    ok, service, log = perform_order(order, {"pma_default" => [:defer]})

    assert ok, service.errors.inspect
    assert_equal %w[elasticsearch_default nginx_default pma_default], log
    assert order.reload.success?
  end

  test "two identical products are both built" do
    order = create_order(%i[pma_default pma_default])

    ok, service, log = perform_order(order)

    assert ok, service.errors.inspect
    assert_equal %w[pma_default pma_default], log
  end

  # --- why the order failed -------------------------------------------------------------

  test "the failure reason is the order's errors, and survives a reload" do
    order = create_order(%i[pma_default])
    service = ProcessOrderService.new(order)
    service.event = @event
    service.errors = ["image is gone", "no capacity"]

    service.send(:fail_process!, "Failed to provision all resources")

    order.reload
    assert order.failed?
    assert_equal "image is gone; no capacity", order.order_data["failure_reason"]
    assert_equal "image is gone; no capacity", order.data[:failure_reason]
    detail = @event.event_details.find_by(event_code: "1adee2a19e284b32")
    assert_equal "ProcessOrderService error output:\n\nimage is gone\nno capacity", detail.data
  end

  test "with no errors, the failure reason and error output are the fail message" do
    order = create_order(%i[pma_default])
    service = ProcessOrderService.new(order)
    service.event = @event

    service.send(:fail_process!, "Over quota")

    assert_equal "Over quota", order.reload.order_data["failure_reason"]
    detail = @event.event_details.find_by(event_code: "1adee2a19e284b32")
    refute_nil detail, "the error output must be written even with no errors"
    assert_match "Over quota", detail.data
  end

  test "with no errors and no message, the failure is still recorded" do
    order = create_order(%i[pma_default])
    service = ProcessOrderService.new(order)
    service.event = @event

    service.send(:fail_process!)

    assert_equal "Unknown failure", order.reload.order_data["failure_reason"]
    refute_nil @event.event_details.find_by(event_code: "1adee2a19e284b32")
  end

  test "an exception during the order is named in the failure reason" do
    order = create_order(%i[pma_default])
    order.current_event = @event
    service = ProcessOrderService.new(order)

    service.stub(:valid?, -> { raise ArgumentError, "bad product params" }) do
      assert_raises(ArgumentError) { service.perform }
    end

    order.reload
    assert order.failed?
    assert_equal "Fatal Error; ArgumentError: bad product params", order.order_data["failure_reason"]
    assert_match "ArgumentError: bad product params",
      @event.event_details.find_by(event_code: "1adee2a19e284b32").data
  end

  test "a long failure reason is truncated" do
    order = create_order(%i[pma_default])
    service = ProcessOrderService.new(order)
    service.event = @event
    service.errors = ["x" * 5_000]

    service.send(:fail_process!, "boom")

    assert_operator order.reload.order_data["failure_reason"].length, :<=, 1_000
  end
end
