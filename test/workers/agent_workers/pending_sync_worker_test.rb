require "test_helper"
require "minitest/mock"

##
# §11 replay (AgentWorkers::PendingSyncWorker) and the trash-side tombstone/deprovision.
class AgentWorkers::PendingSyncWorkerTest < ActiveSupport::TestCase
  setup do
    @project = deployments(:project_test)
    @region = regions(:regionone)
    @node = nodes(:testone)
    @sftp = @project.sftp_containers.first
    @worker = AgentWorkers::PendingSyncWorker.new
  end

  def rec(kind, project: @project, node: nil, key: "", region: @region)
    Agent::PendingSync.record!(region: region, project: project, node: node, kind: kind, key: key, error: "dropped")
    Agent::PendingSync.scope_for(region: region, project: project, node: node, kind: kind, key: key).first
  end

  # Records every agent call (in order) across Agent::Client.new / .for_node.
  def with_fake(fake = FakeAgentClient.new)
    Agent::Client.stub(:new, ->(*, **) { fake }) do
      Agent::Client.stub(:for_node, ->(*) { fake }) { yield fake }
    end
  end

  def run_pass
    @worker.perform(@region.id)
  end

  def other_region
    @other_region ||= Region.create!(name: "dev2", location: locations(:testlocation), volume_backend: "local",
      network_driver: "bridge", p_net_size: 28, log_client: @region.log_client, metric_client: @region.metric_client)
  end

  # --- happy path, ordering, recompute ---------------------------------------------

  test "replays in order: firewall, tenant_delete, tenant, then managed; deletes on success" do
    other = deployments(:user_project_test)
    rec("managed_sftp_host_keys", key: @sftp.name)
    rec("managed_ssh_keys")
    rec("managed_metadata")
    rec("tenant")
    rec("tenant_delete", project: 987_654)
    rec("firewall", project: nil, node: @node)
    calls = nil
    with_fake { |fake| run_pass; calls = fake.calls.map(&:first) }
    assert_equal %i[put_firewall_rules deprovision_tenant! provision_tenant! put_managed put_managed put_managed], calls
    assert_equal 0, AgentPendingSync.count
    assert other # untouched fixture
  end

  test "replay recomputes from CURRENT data (ssh keys changed between drop and replay)" do
    rec("managed_ssh_keys")
    key = @project.project_ssh_keys.create!(label: "late", pubkey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl late@example")
    body = nil
    with_fake { |fake| run_pass; body = fake.last_call(:put_managed)[2] }
    assert_includes JSON.parse(body)["ssh_keys"], key.reload.pubkey
  end

  test "managed replay never self-heals" do
    rec("managed_metadata")
    with_fake { |fake| run_pass; assert_equal [false], fake.put_managed_self_heals }
  end

  test "firewall: recorded drop is replayed by recomputing the node's rules" do
    rec("firewall", project: nil, node: @node)
    with_fake do |fake|
      run_pass
      host, rules = fake.last_call(:put_firewall_rules)[1..]
      assert_equal @node.hostname, host
      assert rules.key?(:rules)
    end
    assert_equal 0, AgentPendingSync.count
  end

  test "a successful replay does not delete a drop recorded during it" do
    rec("managed_metadata")
    fake = FakeAgentClient.new(put_managed: ->(*) {
      rec("managed_metadata")
      true
    })
    with_fake(fake) { run_pass }
    assert_equal 2, AgentPendingSync.sole.generation
  end

  # --- subject resolution ------------------------------------------------------------

  test "a gone project, sftp or node drops the row without a push" do
    rec("managed_sftp_host_keys", key: "no-such-sftp")
    AgentPendingSync.insert_all!([{region_id: @region.id, project_id: 987_654, kind: "managed_metadata", key: "",
                                   generation: 1, next_attempt_at: Time.current, created_at: Time.current, updated_at: Time.current}])
    with_fake { |fake| run_pass; assert_empty fake.calls }
    assert_equal 0, AgentPendingSync.count
  end

  test "an sftp row is resolved within its own project" do
    other = deployments(:user_project_test)
    other_sftp = other.sftp_containers.first
    # Same name in the wrong project must not resolve.
    rec("managed_sftp_host_keys", key: other_sftp.name)
    with_fake { |fake| run_pass; assert_empty fake.calls }
    assert_equal 0, AgentPendingSync.count
  end

  test "a row whose subject moved to another region is dropped" do
    other_region
    rec("managed_metadata", region: other_region)
    other_node = Node.new(label: "n2", hostname: "n2", primary_ip: "10.9.9.9", public_ip: "10.9.9.9", region: other_region)
    other_node.save!(validate: false)
    with_fake { |fake| @worker.perform(other_region.id); assert_empty fake.calls }
    assert_equal 0, AgentPendingSync.count
  end

  test "a tombstoned project's managed rows are dropped, never pushed" do
    r = rec("managed_metadata")
    Agent::TenantRegistry.tombstone!(@project.id, [@region.id])
    assert AgentPendingSync.exists?(r.id)
    with_fake { |fake| run_pass; assert_empty fake.calls }
    assert_equal 0, AgentPendingSync.count
  end

  # --- no node / transport / backoff / dead -------------------------------------------

  test "no reachable node: skipped with no attempt and no age" do
    r = rec("managed_metadata")
    @node.update_columns(disconnected: true)
    with_fake { |fake| run_pass; assert_empty fake.calls }
    r.reload
    assert_equal 0, r.attempts
    assert_nil r.first_attempted_at
    assert_nil r.dead_at
  end

  test "a node in maintenance is used for replay" do
    rec("managed_metadata")
    @node.update_columns(maintenance_requested: true)
    with_fake { |fake| run_pass; assert fake.called?(:put_managed) }
    assert_equal 0, AgentPendingSync.count
  end

  test "a transport failure stops the region: no attempt counted, the rest deferred untouched" do
    fw = rec("firewall", project: nil, node: @node)
    meta = rec("managed_metadata")
    keys = rec("managed_ssh_keys")
    fake = FakeAgentClient.new(put_firewall_rules: ->(*) { raise HTTP::ConnectionError, "down" })
    with_fake(fake) { run_pass }
    assert_equal [:put_firewall_rules], fake.calls.map(&:first)
    fw.reload
    assert_equal 0, fw.attempts, "the agent was never reached"
    assert_nil fw.first_attempted_at
    assert fw.last_attempt_at
    assert_in_delta 2.minutes.from_now, fw.next_attempt_at, 5
    assert_match "HTTP::ConnectionError", fw.last_error
    [meta, keys].each do |r|
      r.reload
      assert_equal 0, r.attempts
      assert_nil r.first_attempted_at
      assert r.next_attempt_at > Time.current
    end
  end

  test "a refused push backs off exponentially, capped at 30 minutes" do
    r = rec("managed_metadata")
    with_fake(FakeAgentClient.new(put_managed: false)) { run_pass }
    r.reload
    assert_equal 1, r.attempts
    assert_in_delta 2.minutes.from_now, r.next_attempt_at, 5
    assert r.first_attempted_at

    r.update_columns(attempts: 9, next_attempt_at: Time.current)
    with_fake(FakeAgentClient.new(put_managed: false)) { run_pass }
    assert_in_delta 30.minutes.from_now, r.reload.next_attempt_at, 5
  end

  test "a refused push does not count against a drop recorded during it" do
    r = rec("managed_metadata")
    fake = FakeAgentClient.new(put_managed: ->(*) {
      rec("managed_metadata")
      false
    })
    with_fake(fake) { run_pass }
    r.reload
    assert_equal 0, r.attempts
    assert_equal 2, r.generation
  end

  test "dead after 24 attempts: one SystemEvent, and it is no longer replayed" do
    r = rec("managed_metadata")
    r.update_columns(attempts: 23, first_attempted_at: 1.hour.ago)
    assert_difference -> { SystemEvent.where(event_code: "9d2c4e71b0a8f365").count }, 1 do
      with_fake(FakeAgentClient.new(put_managed: false)) { run_pass }
    end
    assert r.reload.dead_at
    with_fake { |fake| run_pass; assert_empty fake.calls }
  end

  test "dead after 48 h since the first REAL attempt, not since the first failure" do
    r = rec("managed_metadata")
    r.update_columns(first_failed_at: 5.days.ago)
    with_fake(FakeAgentClient.new(put_managed: false)) { run_pass }
    assert_nil r.reload.dead_at, "an outage longer than 48 h must not kill an untried row"

    r.update_columns(first_attempted_at: 49.hours.ago, next_attempt_at: Time.current)
    with_fake(FakeAgentClient.new(put_managed: false)) { run_pass }
    assert r.reload.dead_at
  end

  test "transport failures never mark a row dead, however long the outage" do
    r = rec("managed_metadata")
    r.update_columns(attempts: 23, first_failed_at: 5.days.ago)
    fake = FakeAgentClient.new(put_managed: ->(*) { raise HTTP::ConnectionError, "down" })
    assert_no_difference -> { SystemEvent.where(event_code: "9d2c4e71b0a8f365").count } do
      3.times do
        with_fake(fake) { run_pass }
        r.update_columns(next_attempt_at: Time.current)
      end
    end
    r.reload
    assert_nil r.dead_at
    assert_equal 23, r.attempts
    assert_nil r.first_attempted_at
  end

  test "rows stuck only on transport failures still raise the stale SystemEvent" do
    r = rec("managed_metadata")
    r.update_columns(first_failed_at: 2.hours.ago)
    fake = FakeAgentClient.new(put_managed: ->(*) { raise HTTP::ConnectionError, "down" })
    assert_difference -> { SystemEvent.where(event_code: "5a0e8f3c2b7d6194").count }, 1 do
      with_fake(fake) { run_pass }
    end
    assert_nil r.reload.first_attempted_at
  end

  test "a live row over an hour past its recorded drop raises one stale SystemEvent per region per 6 h" do
    r = rec("managed_metadata")
    r.update_columns(first_failed_at: 2.hours.ago)
    assert_difference -> { SystemEvent.where(event_code: "5a0e8f3c2b7d6194").count }, 1 do
      with_fake(FakeAgentClient.new(put_managed: false)) do
        run_pass
        r.update_columns(next_attempt_at: Time.current)
        run_pass
      end
    end
    assert_equal({"managed_metadata" => 1}, SystemEvent.where(event_code: "5a0e8f3c2b7d6194").last.data["kinds"])
  end

  test "no args fans out one job per region with due rows" do
    rec("managed_metadata")
    enqueued = []
    AgentWorkers::PendingSyncWorker.stub(:perform_async, ->(*args) { enqueued << args }) { @worker.perform }
    assert_equal [[@region.id]], enqueued
  end

  # --- trash / tombstone / deprovision ------------------------------------------------

  def trash_service
    ProjectServices::TrashProject.new(@project, EventLog.new)
  end

  test "trash tombstones BEFORE any deprovision call" do
    seen = []
    fake = FakeAgentClient.new(deprovision_tenant!: ->(*) {
      seen << Agent::TenantRegistry.deleting?(@project.id)
      true
    })
    with_fake(fake) { trash_service.send(:clean_metadata_tenant!) }
    assert_equal [true], seen
  end

  test "trash deprovisions registry, container and sftp regions, deleting pending rows but keeping the tombstone" do
    other_region
    AgentTenant.create!(project_id: @project.id, region_id: other_region.id, provisioned_at: Time.current)
    rec("managed_metadata")
    regions_called = []
    Agent::Client.stub(:for_project_id, ->(pid, region:) {
      regions_called << [pid, region.id]
      FakeAgentClient.new
    }) { trash_service.send(:clean_metadata_tenant!) }
    assert_equal [[@project.id, @region.id], [@project.id, other_region.id]].sort, regions_called.sort
    assert_equal 2, AgentTenant.where(project_id: @project.id).where.not(deleting_at: nil).count,
      "the project still exists: the tombstone outlives the deprovision"
    assert Agent::TenantRegistry.deleting?(@project.id)
    assert_equal 0, AgentPendingSync.where(project_id: @project.id).count
  end

  # Runs TrashProject#perform with the container side stubbed out.
  def trash_perform(trash_services: true, destroy: true, &during)
    event = EventLog.create!(locale: "deployment.trash", event_code: "0f3d8a6b2c91e475", status: "running")
    svc = ProjectServices::TrashProject.new(@project, event)
    trash = -> {
      during&.call
      raise trash_services if trash_services.is_a?(Exception)
      trash_services
    }
    destroyer = -> {
      next false unless destroy
      @project.delete
      true
    }
    result = nil
    svc.stub(:valid?, true) do
      svc.stub(:trash_sftp_containers!, nil) do
        svc.stub(:trash_services!, trash) do
          @project.stub(:destroy, destroyer) do
            @project.stub(:reload, @project) do
              with_fake { result = svc.perform }
            end
          end
        end
      end
    end
    result
  end

  test "trash: deleting? stays true between a successful deprovision and the destroy" do
    seen = nil
    assert trash_perform { seen = Agent::TenantRegistry.deleting?(@project.id) }
    assert_equal true, seen
  end

  test "trash success forgets the registry rows; the project is gone so deleting? holds" do
    rec("managed_metadata")
    pid = @project.id
    assert trash_perform
    assert_equal 0, AgentTenant.where(project_id: pid).count
    assert_equal 0, AgentPendingSync.where(project_id: pid).count
    assert Agent::TenantRegistry.deleting?(pid)
  end

  test "trash success keeps a tenant_delete still owed to an agent" do
    pid = @project.id
    Agent::Client.stub(:for_project_id, ->(*, **) { FakeAgentClient.new(deprovision_tenant!: false) }) do
      assert trash_perform
    end
    assert_equal ["tenant_delete"], AgentPendingSync.where(project_id: pid).pluck(:kind)
    assert_equal 0, AgentTenant.where(project_id: pid).count
  end

  test "trash aborting after the deprovision (trash_services! false) lifts the tombstone" do
    Agent::Client.stub(:for_project_id, ->(*, **) { FakeAgentClient.new(deprovision_tenant!: false) }) do
      refute trash_perform(trash_services: false)
    end
    assert Deployment.exists?(@project.id)
    refute Agent::TenantRegistry.deleting?(@project.id)
    assert_equal 0, AgentTenant.where(project_id: @project.id).where.not(deleting_at: nil).count
    assert_empty AgentPendingSync.where(project_id: @project.id, kind: "tenant_delete")

    # Managed writes push again (and self-heal the deprovisioned tenant).
    fake = FakeAgentClient.new
    Agent::Client.stub(:new, ->(*, **) { fake }) do
      ProjectServices::StoreMetadata.new(@project).perform
    end
    assert fake.called?(:put_managed)
    assert Agent::PendingSync.record!(region: @region, project: @project.id, kind: "managed_metadata", error: "x")
  end

  test "trash aborting on a failed destroy or an exception lifts the tombstone" do
    refute trash_perform(destroy: false)
    refute Agent::TenantRegistry.deleting?(@project.id)

    assert_raises(RuntimeError) { trash_perform(trash_services: RuntimeError.new("boom")) }
    refute Agent::TenantRegistry.deleting?(@project.id)
  end

  test "trash aborting marks the tenant and its managed blobs dirty so replay rebuilds them" do
    refute trash_perform(trash_services: false)
    kinds = AgentPendingSync.where(project_id: @project.id, region_id: @region.id).pluck(:kind)
    assert_equal %w[managed_metadata managed_ssh_keys tenant], (kinds - ["managed_sftp_host_keys"]).sort
    if @sftp&.region&.id == @region.id
      assert AgentPendingSync.exists?(project_id: @project.id, kind: "managed_sftp_host_keys", key: @sftp.name)
    end
  end

  test "lifting the tombstone is a no-op once the project is gone" do
    pid = @project.id
    Agent::TenantRegistry.tombstone!(pid, [@region.id])
    rec("tenant_delete")
    @project.delete
    Agent::TenantRegistry.lift_tombstone!(pid)
    assert_equal ["tenant_delete"], AgentPendingSync.where(project_id: pid).pluck(:kind)
    assert AgentTenant.find_by(project_id: pid, region_id: @region.id).deleting_at
  end

  test "a replayed tenant_delete for a project that still exists keeps the tombstone" do
    Agent::TenantRegistry.tombstone!(@project.id, [@region.id])
    rec("tenant_delete")
    Agent::Client.stub(:for_project_id, ->(*, **) { FakeAgentClient.new }) do
      with_fake { run_pass }
    end
    assert_equal 0, AgentPendingSync.where(project_id: @project.id).count
    assert AgentTenant.find_by(project_id: @project.id, region_id: @region.id).deleting_at
    assert Agent::TenantRegistry.deleting?(@project.id)
  end

  test "an sftp container's region is deprovisioned even when nothing else names it" do
    other_node = Node.new(label: "n2", hostname: "n2", primary_ip: "10.9.9.9", public_ip: "10.9.9.9", region: other_region)
    other_node.save!(validate: false)
    @sftp.update_columns(node_id: other_node.id)
    AgentTenant.delete_all
    regions_called = []
    Agent::Client.stub(:for_project_id, ->(pid, region:) {
      regions_called << region.id
      FakeAgentClient.new
    }) { trash_service.send(:clean_metadata_tenant!) }
    assert_equal [@region.id, other_region.id].sort, regions_called.sort
  end

  test "the reviewer's scenario: pending managed row, successful trash, replay never re-provisions" do
    rec("managed_metadata")
    rec("tenant")
    with_fake { trash_service.send(:clean_metadata_tenant!) }
    @project.delete
    # A late live writer can't re-dirty it either.
    refute Agent::PendingSync.record!(region: @region, project: @project.id, kind: "managed_metadata", error: "late")
    with_fake { |fake| run_pass; assert_empty fake.calls }
  end

  test "a failed deprovision becomes a tenant_delete that replays after the Project row is gone" do
    rec("managed_metadata")
    with_fake(FakeAgentClient.new(deprovision_tenant!: false)) { trash_service.send(:clean_metadata_tenant!) }
    assert_equal ["tenant_delete"], AgentPendingSync.where(project_id: @project.id).pluck(:kind)
    assert AgentTenant.find_by(project_id: @project.id, region_id: @region.id).deleting_at
    pid = @project.id
    @project.delete

    called = []
    Agent::Client.stub(:for_project_id, ->(id, region:) {
      called << id
      FakeAgentClient.new
    }) do
      with_fake { |fake| run_pass; refute fake.called?(:provision_tenant!) }
    end
    assert_equal [pid], called
    assert_equal 0, AgentPendingSync.count
    assert_equal 0, AgentTenant.where(project_id: pid).count
  end

  test "a NotReady deprovision is recorded too" do
    Agent::Client.stub(:for_project_id, ->(*, **) { raise Agent::Client::NotReady, "no node" }) do
      trash_service.send(:clean_metadata_tenant!)
    end
    assert_match "no node", AgentPendingSync.find_by(kind: "tenant_delete").last_error
  end

  # --- triggers ----------------------------------------------------------------------

  test "leaving maintenance enqueues a replay for the node's region" do
    enqueued = []
    AgentWorkers::PendingSyncWorker.stub(:perform_async, ->(*args) { enqueued << args }) do
      Nodes::MaintenanceTransitions.kick_recovery!(@node)
    end
    assert_equal [[@region.id]], enqueued
  end
end
