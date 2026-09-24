require "test_helper"
require "minitest/mock"

##
# The unit of work behind the image volume-param cascade: attach ONE image volume template to
# ONE already-deployed container service, creating the Volume row, its owner VolumeMap and the
# real docker volume, without rebuilding or restarting anything.
#
# The invariants worth defending here are the ones that were actively broken before:
#   * a validation conflict (the nested mount path case) is a reported skip, not a crash that
#     leaves an orphan Volume row behind on every retry;
#   * volume + map commit in ONE transaction, so `after_commit :set_detached` never stamps
#     detached_at and no phantom "Detached Volume" subscription appears;
#   * the docker volume is positively asserted, and a failure rolls BOTH rows back -- a mount
#     in a service's config pointing at a volume absent from the node is auto-created by
#     Docker at the next rebuild with the `local` driver and no labels;
#   * offline / multi-node target sets are refused rather than "successfully" provisioned.
class VolumeServices::AttachTemplateVolumeServiceTest < ActiveSupport::TestCase
  # Stands in for DockerVolumeLocal::Volume. Stubbing DockerVolumeLocal::Volume.new covers
  # every `volume.volume_client` call in the whole path (ours AND ProvisionVolumeService's),
  # which is the only way to keep the real docker/SSH transport out of these tests.
  class FakeDriver
    attr_reader :errors, :calls

    # @param provisioned [Boolean, Array<Boolean>] an Array is consumed one answer per call
    def initialize(create: true, provisioned: true, destroy: true)
      @create = create
      @provisioned = provisioned
      @destroy = destroy
      @errors = []
      @calls = []
    end

    def create!
      @calls << :create!
      @errors << "Fatal error provisioning volume on node: test01" unless @create
      @create
    end

    def provisioned?
      @calls << :provisioned?
      @provisioned.is_a?(Array) ? @provisioned.shift : @provisioned
    end

    def destroy
      @calls << :destroy
      @destroy
    end

    def called?(kind) = @calls.include?(kind)

    def count_of(kind) = @calls.count(kind)
  end

  setup do
    @event = EventLog.create!(
      locale: "image.cascade_volume",
      locale_keys: {"image" => container_images(:custom).name},
      event_code: "91c08ca8a3617fbc",
      status: "pending"
    )
    @param = container_image_volume_params(:custom_files) # image: custom, /mnt/data
    @service = deployment_container_services(:wordpress_custom) # variant custom_default, node testone
  end

  # Runs the block with the docker driver and the agent transport replaced.
  def with_stubs(driver: nil, agent: nil)
    driver ||= FakeDriver.new
    agent ||= FakeAgentClient.new
    DockerVolumeLocal::Volume.stub(:new, driver) do
      Agent::Client.stub(:for_node, agent) do
        yield driver, agent
      end
    end
  end

  def attach(param = @param, service = @service)
    VolumeServices::AttachTemplateVolumeService.new(param, service, @event)
  end

  def details = @event.event_details.reload.map(&:data)

  # --- the happy path ---------------------------------------------------------------

  test "creates the volume and its owner map, awaiting mount, with nodes populated" do
    svc = with_stubs do |_driver, _agent|
      s = attach
      assert_equal :created, s.perform, s.message
      s
    end

    volume = svc.volume.reload
    map = svc.volume_map.reload

    assert_equal @param, volume.template
    assert_equal @param.label, volume.label
    assert_equal @service.deployment, volume.deployment
    assert_equal @service.deployment.user, volume.user
    assert_equal @service.region, volume.region
    assert_equal "local", volume.volume_backend
    assert volume.awaiting_mount, "a cascaded volume is not mounted by any container yet"
    assert_equal [nodes(:testone)], volume.nodes.to_a,
      "nodes drives create!, the runtime_config bind filter and update_consul!'s node choice"

    assert_equal volume, map.volume
    assert_equal @service, map.container_service
    assert_equal "/mnt/data", map.mount_path
    assert map.is_owner
    refute map.mount_ro

    assert_equal 1, details.count, "exactly one event detail line per call"
    assert_match(/Created volume/, details.first)
  end

  # The single transaction is the whole point: a volume that commits before its map exists gets
  # detached_at stamped by after_commit :set_detached, and CollectUsageService#offline_storage
  # then opens a "Detached Volume" subscription for a volume that may stay pending for weeks.
  test "the volume never looks detached, so no phantom detached subscription is created" do
    svc = with_stubs { attach.tap { |s| assert_equal :created, s.perform, s.message } }

    assert_nil svc.volume.reload.detached_at
    assert_nil svc.volume.subscription
  end

  test "the volume is provisioned on the node and positively asserted" do
    with_stubs do |driver, agent|
      assert_equal :created, attach.perform
      assert driver.called?(:create!), "the docker volume must actually be created"
      assert driver.called?(:provisioned?), "and its presence positively asserted"
      assert agent.called?(:put_volume), "desired state is pushed to the agent"
      _, _project, _name, desired = agent.last_call(:put_volume)
      assert_equal false, desired[:backup],
        "borg must stay suppressed while nothing has the volume mounted"
    end
  end

  test "is idempotent: a second run skips instead of creating a duplicate" do
    with_stubs { assert_equal :created, attach.perform }

    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      with_stubs do
        second = attach
        assert_equal :skipped, second.perform
        assert_match %r{already has a volume mounted at /mnt/data}, second.message
      end
    end
  end

  # --- refusals --------------------------------------------------------------------

  test "refuses a reference volume param" do
    ref = container_image_volume_params(:nginx_mounted)
    assert ref.source_volume.present?, "fixture sanity"

    assert_no_difference "Volume.count" do
      s = attach(ref, deployment_container_services(:nginx))
      assert_equal :skipped, s.perform
      assert_match(/reference to another volume/, s.message)
    end
  end

  test "refuses a service whose project is being deleted" do
    @service.deployment.update_columns(status: "deleting")

    assert_no_difference "Volume.count" do
      s = attach
      assert_equal :skipped, s.perform
      assert_match(/project is being deleted/, s.message)
    end
  end

  test "skips when the mount path is already in use on the service" do
    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      with_stubs do
        s = attach(container_image_volume_params(:mysql_data), deployment_container_services(:mysql))
        assert_equal :skipped, s.perform
        assert_match %r{already has a volume mounted at /var/lib/mysql}, s.message
      end
    end
  end

  # The path is free, but a volume from this template is already mounted elsewhere on the
  # service. Queried through volume_maps, never through service.volumes (which by construction
  # only ever returns volumes that already have a map).
  test "skips when a map already points at a volume from this template" do
    volumes(:mysql).update_columns(template_id: @param.id)

    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      with_stubs do
        s = attach(@param, deployment_container_services(:mysql))
        assert_equal :skipped, s.perform
        assert_match(/already has a volume from this template/, s.message)
      end
    end
  end

  # --- healing the node side on the skip paths --------------------------------------

  # The resume path for a run killed between the DB commit and provisioning: the rows exist so
  # the dedupe short-circuits, but the docker volume does not. Re-running the retroactive
  # cascade has to repair that rather than report a healthy skip over a broken volume.
  test "heals a missing docker volume on the already-mapped skip path" do
    driver = FakeDriver.new(provisioned: false)

    with_stubs(driver: driver) do
      s = attach(container_image_volume_params(:mysql_data), deployment_container_services(:mysql))
      assert_equal :skipped, s.perform
      assert_match(/has been re-provisioned/, s.message)
    end

    assert driver.called?(:create!), "the missing docker volume is created on the node"
  end

  test "heals a missing docker volume on the already-from-this-template skip path" do
    volumes(:mysql).update_columns(template_id: @param.id)
    driver = FakeDriver.new(provisioned: false)

    with_stubs(driver: driver) do
      s = attach(@param, deployment_container_services(:mysql))
      assert_equal :skipped, s.perform
      assert_match(/already has a volume from this template/, s.message)
      assert_match(/has been re-provisioned/, s.message)
    end

    assert driver.called?(:create!)
  end

  test "does not try to verify the node side when the volume has no online node" do
    nodes(:testone).update_columns(maintenance: true)
    driver = FakeDriver.new(provisioned: false)

    with_stubs(driver: driver) do
      s = attach(container_image_volume_params(:mysql_data), deployment_container_services(:mysql))
      assert_equal :skipped, s.perform
      assert_match %r{already has a volume mounted at /var/lib/mysql}, s.message
      refute_match(/re-provisioned/, s.message)
    end

    refute driver.called?(:create!), "provisioned? is unfalsifiable against an offline node"
  end

  # --- validation conflicts leave nothing behind ------------------------------------

  # This is the case that crashes today: VolumeMap#no_nested_volumes rejects a path that is a
  # prefix of (or prefixed by) an existing map, and the old worker saved the Volume BEFORE
  # validating the map -- one orphan Volume row per retry, times 25 retries.
  test "a nested mount path conflict is a clean skip with no orphan volume" do
    VolumeMap.create!(
      volume: volumes(:nginx_web),
      container_service: @service,
      mount_path: "/mnt/data/deep",
      mount_ro: false,
      is_owner: false
    )

    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      with_stubs do |driver, _agent|
        s = attach
        assert_equal :skipped, s.perform
        assert_match(/mount is invalid/, s.message)
        assert_match(/already in use/, s.message)
        refute driver.called?(:create!), "nothing may be provisioned on a rejected attach"
      end
    end
  end

  # The uniqueness VALIDATION cannot see a row a concurrent transaction has not committed yet,
  # so the unique index on volume_maps (container_service_id, mount_path) is the real authority
  # and the loser of that race must land somewhere sane. There is deliberately no
  # sidekiq-unique-jobs lock in front of this (see AttachVolumeToServiceWorker): dropping the
  # duplicate child would leave the second cascade's event counter permanently short.
  # The DB guard itself. Nothing else in the suite covers the index, and it is the only thing
  # standing between two concurrent cascades and a service that can never be rebuilt again.
  test "the unique index rejects a second owner map at one path on one service" do
    map = volume_maps(:nginx_web_vol_map)
    assert_raises ActiveRecord::RecordNotUnique do
      # insert_all! bypasses validations and callbacks, so only the index can refuse this --
      # and unlike insert_all it does NOT add ON CONFLICT DO NOTHING, so a violation raises.
      # Wrapped in a savepoint so the aborted statement does not poison the test transaction.
      ActiveRecord::Base.transaction(requires_new: true) do
        VolumeMap.insert_all!([{
          volume_id: volumes(:mysql).id,
          container_service_id: map.container_service_id,
          mount_path: map.mount_path,
          mount_ro: false,
          is_owner: true,
          created_at: Time.now.utc,
          updated_at: Time.now.utc
        }])
      end
    end
  end

  # The uniqueness VALIDATION cannot see a row a concurrent transaction has not committed yet,
  # so the index above is the real authority and the loser of that race has to land somewhere
  # sane. There is deliberately no sidekiq-unique-jobs lock in front of this (see
  # AttachVolumeToServiceWorker) -- dropping the duplicate child would leave the second
  # cascade's event counter permanently short and its event reaped as "cancelled".
  test "losing the unique-index race reports a skip rather than a failure" do
    with_stubs do |driver, _agent|
      s = attach
      first_call = true
      # Stand in for the winner committing between our validation and our insert.
      ActiveRecord::Base.stub(:transaction, ->(*, &blk) {
        if first_call
          first_call = false
          raise ActiveRecord::RecordNotUnique, "PG::UniqueViolation: index_volume_maps_on_service_and_path"
        end
        blk.call
      }) do
        assert_equal :skipped, s.perform
      end
      assert_match(/concurrently/, s.message)
      refute driver.called?(:create!), "nothing may be provisioned when the insert lost the race"
    end
  end

  # --- node selection --------------------------------------------------------------

  test "skips a service with no node" do
    assert_no_difference "Volume.count" do
      @service.stub(:nodes, []) do
        with_stubs do
          s = attach
          assert_equal :skipped, s.perform
          assert_match(/no node/, s.message)
        end
      end
    end
  end

  # DockerVolumeLocal::Volume#create! and #provisioned? both `next unless node.online?` and
  # return true when every node was skipped, so a "successful" provision against an offline
  # node would commit a volume that exists nowhere.
  test "skips when a target node is offline" do
    nodes(:testone).update_columns(disconnected: true)

    assert_no_difference "Volume.count" do
      with_stubs do |driver, _agent|
        s = attach
        assert_equal :skipped, s.perform
        assert_match(/offline/, s.message)
        refute driver.called?(:create!)
      end
    end
  end

  # runtime_config filters binds by the CONTAINER's node, so a local volume attached to one
  # node of a two-node service silently gives the replicas divergent filesystems.
  test "skips a local-backend service that spans more than one node" do
    two = [nodes(:testone), Node.new(hostname: "test02")]

    assert_no_difference "Volume.count" do
      @service.stub(:nodes, two) do
        with_stubs do
          s = attach
          assert_equal :skipped, s.perform
          assert_match(/spans multiple nodes/, s.message)
        end
      end
    end
  end

  test "an nfs backend targets every node in the region and tolerates more than one" do
    regions(:regionone).update_columns(volume_backend: "nfs")
    fake_nfs = FakeDriver.new

    Agent::Client.stub(:for_node, FakeAgentClient.new) do
      DockerVolumeNfs.stub(:configure, true) do
        DockerVolumeNfs::Volume.stub(:new, fake_nfs) do
          s = attach
          assert_equal :created, s.perform, s.message
          assert_equal "nfs", s.volume.volume_backend
          assert_equal regions(:regionone).nodes.to_a, s.volume.nodes.to_a
        end
      end
    end
  end

  # --- provisioning failure rolls everything back -----------------------------------

  test "rolls both rows back and fails when the driver cannot create the volume" do
    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      with_stubs(driver: FakeDriver.new(create: false)) do |driver, agent|
        s = attach
        assert_equal :failed, s.perform
        assert_match(/^Failed /, s.message)
        assert driver.called?(:destroy), "any partially created docker volume is torn down"
        assert agent.called?(:delete_volume), "the agent-side volume row is deleted too"
      end
    end

    refute Volume.exists?(template_id: @param.id), "no orphan volume row survives"
    assert_match(/Failed/, details.last)
  end

  # create! reports success but the volume is not actually there. Without the positive
  # assertion this would commit a mount pointing at nothing.
  test "rolls back when the positive provisioned? assertion fails" do
    assert_no_difference ["Volume.count", "VolumeMap.count"] do
      with_stubs(driver: FakeDriver.new(provisioned: [false])) do |driver, _agent|
        s = attach
        assert_equal :failed, s.perform
        assert driver.called?(:create!)
      end
    end
  end

  test "a rolled back attach leaves no node join rows behind" do
    before = ActiveRecord::Base.connection.select_value("SELECT count(*) FROM nodes_volumes").to_i

    with_stubs(driver: FakeDriver.new(create: false)) { assert_equal :failed, attach.perform }

    after = ActiveRecord::Base.connection.select_value("SELECT count(*) FROM nodes_volumes").to_i
    assert_equal before, after
  end

  # --- never raises ----------------------------------------------------------------

  test "an unexpected error is reported as a failure rather than raised" do
    boom = ->(*) { raise "boom" }

    ExceptionAlertService.stub(:new, Struct.new(:x).new(nil).tap { |o| o.define_singleton_method(:perform) { true } }) do
      VolumeMap.stub(:safe_mount, boom) do
        s = attach
        assert_equal :failed, s.perform
        assert_match(/unexpected error: boom/, s.message)
      end
    end
  end
end
