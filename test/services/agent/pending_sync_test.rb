require "test_helper"
require "minitest/mock"

##
# §11 Agent::PendingSync / Agent::TenantRegistry semantics, and every live call site
# recording on NotReady and on false.
class Agent::PendingSyncTest < ActiveSupport::TestCase
  setup do
    @project = deployments(:project_test)
    @region = regions(:regionone)
    @node = nodes(:testone)
    @sftp = @project.sftp_containers.first
  end

  def row(kind, key: "", project: @project, node: nil)
    Agent::PendingSync.scope_for(region: @region, project: project, node: node, kind: kind, key: key).first
  end

  # --- record! --------------------------------------------------------------------

  test "record! upserts: one row, generation bumped, first_failed_at kept, last_error replaced" do
    travel_to 1.hour.ago do
      assert Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "first")
    end
    first = row("managed_metadata")
    assert_equal 1, first.generation
    assert_equal "first", first.last_error

    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "second")
    assert_equal 1, AgentPendingSync.count
    r = row("managed_metadata")
    assert_equal 2, r.generation
    assert_equal "second", r.last_error
    assert_in_delta first.first_failed_at, r.first_failed_at, 1
    assert_in_delta Time.current, r.next_attempt_at, 5
  end

  test "record! keys rows by kind and key" do
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_sftp_host_keys", key: "a", error: "x")
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_sftp_host_keys", key: "b", error: "x")
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_ssh_keys", error: "x")
    Agent::PendingSync.record!(region: @region, node: @node, kind: "firewall", error: "x")
    assert_equal 4, AgentPendingSync.count
  end

  test "record! clears dead_at, and a revived dead row starts its attempts afresh" do
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    row("managed_metadata").update_columns(dead_at: Time.current, attempts: 24, first_attempted_at: 3.days.ago)
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "y")
    r = row("managed_metadata")
    assert_nil r.dead_at
    assert_equal 0, r.attempts
    assert_nil r.first_attempted_at
  end

  test "record! keeps the attempt count of a live row" do
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    row("managed_metadata").update_columns(attempts: 3, first_attempted_at: 1.hour.ago)
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "y")
    assert_equal 3, row("managed_metadata").attempts
  end

  test "tenant_delete supersedes every other row for that (region, project)" do
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    Agent::PendingSync.record!(region: @region, project: @project, kind: "tenant", error: "x")
    Agent::PendingSync.record!(region: @region, project: deployments(:user_project_test), kind: "tenant", error: "x")
    Agent::PendingSync.record!(region: @region, project: @project, kind: "tenant_delete", error: "x")
    assert_equal ["tenant_delete"], AgentPendingSync.where(project_id: @project.id).pluck(:kind)
    assert_equal 1, AgentPendingSync.where(project_id: deployments(:user_project_test).id).count
  end

  test "the tombstone suppresses record! for non-delete kinds, not for tenant_delete" do
    Agent::TenantRegistry.tombstone!(@project.id, [@region.id])
    refute Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    refute Agent::PendingSync.record!(region: @region, project: @project, kind: "tenant", error: "x")
    assert Agent::PendingSync.record!(region: @region, project: @project, kind: "tenant_delete", error: "x")
    assert_equal ["tenant_delete"], AgentPendingSync.pluck(:kind)
  end

  test "record! is suppressed for a project whose row is gone" do
    refute Agent::PendingSync.record!(region: @region, project: 987_654, kind: "managed_metadata", error: "x")
    assert_equal 0, AgentPendingSync.count
  end

  # --- clear! ---------------------------------------------------------------------

  test "clear! deletes only at the generation read; a newer drop survives a stale success" do
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    gen = Agent::PendingSync.generation_for(region: @region, project: @project, kind: "managed_metadata")
    # A concurrent writer drops after our read.
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "newer")
    refute Agent::PendingSync.clear!(region: @region, project: @project, kind: "managed_metadata", if_generation: gen)
    assert_equal "newer", row("managed_metadata").last_error

    gen = Agent::PendingSync.generation_for(region: @region, project: @project, kind: "managed_metadata")
    assert Agent::PendingSync.clear!(region: @region, project: @project, kind: "managed_metadata", if_generation: gen)
    assert_nil row("managed_metadata")
  end

  test "clear! with no row at read time deletes nothing, even a row recorded since" do
    gen = Agent::PendingSync.generation_for(region: @region, project: @project, kind: "managed_metadata")
    assert_nil gen
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    refute Agent::PendingSync.clear!(region: @region, project: @project, kind: "managed_metadata", if_generation: gen)
    assert row("managed_metadata")
  end

  # --- live call sites ------------------------------------------------------------

  def with_client(fake)
    Agent::Client.stub(:new, ->(*, **) { fake }) { yield }
  end

  def not_ready
    ->(*, **) { raise Agent::Client::NotReady, "no reachable node" }
  end

  {
    "managed_metadata" => -> { ProjectServices::StoreMetadata.new(deployments(:project_test)).perform },
    "managed_ssh_keys" => -> { ProjectServices::MetadataSshKeys.new(deployments(:project_test)).perform }
  }.each do |kind, call|
    test "#{kind}: records on false, records on NotReady, clears on success" do
      with_client(FakeAgentClient.new(put_managed: false)) { assert_equal false, instance_exec(&call) }
      assert_equal 1, row(kind).generation

      Agent::Client.stub(:new, not_ready) { assert_equal false, instance_exec(&call) }
      assert_equal 2, row(kind).generation
      assert_match "no reachable node", row(kind).last_error

      with_client(FakeAgentClient.new) { assert instance_exec(&call) }
      assert_nil row(kind)
    end

    test "#{kind}: skips the push entirely while the project is being deleted" do
      Agent::TenantRegistry.tombstone!(@project.id, [@region.id])
      fake = FakeAgentClient.new
      with_client(fake) { assert_equal false, instance_exec(&call) }
      assert_empty fake.calls
      assert_equal 0, AgentPendingSync.count
    end
  end

  test "a live success clears only the drop it covers (generation read before the body)" do
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_ssh_keys", error: "x")
    fake = FakeAgentClient.new(put_managed: ->(*) {
      # A concurrent drop lands while our push is in flight.
      Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_ssh_keys", error: "concurrent")
      true
    })
    with_client(fake) { assert ProjectServices::MetadataSshKeys.new(@project).perform }
    assert_equal "concurrent", row("managed_ssh_keys").last_error
  end

  test "managed_sftp_host_keys: keyed by the sftp name; records on false and NotReady, clears on success" do
    with_client(FakeAgentClient.new(put_managed: false)) { SftpServices::MetadataSshHostKeys.new(@sftp).perform }
    assert row("managed_sftp_host_keys", key: @sftp.name)
    Agent::Client.stub(:new, not_ready) { SftpServices::MetadataSshHostKeys.new(@sftp).perform }
    assert_equal 2, row("managed_sftp_host_keys", key: @sftp.name).generation
    with_client(FakeAgentClient.new) { assert SftpServices::MetadataSshHostKeys.new(@sftp).perform }
    assert_nil row("managed_sftp_host_keys", key: @sftp.name)
  end

  test "live writers self-heal; replay (self_heal: false) does not" do
    fake = FakeAgentClient.new
    with_client(fake) do
      ProjectServices::StoreMetadata.new(@project).perform
      ProjectServices::StoreMetadata.new(@project).perform(record_drop: false, self_heal: false)
    end
    assert_equal [true, false], fake.put_managed_self_heals
  end

  test "replay mode (record_drop: false) neither records nor clears" do
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    with_client(FakeAgentClient.new) { ProjectServices::StoreMetadata.new(@project).perform(record_drop: false) }
    assert row("managed_metadata")
    AgentPendingSync.delete_all
    with_client(FakeAgentClient.new(put_managed: false)) { ProjectServices::StoreMetadata.new(@project).perform(record_drop: false) }
    assert_equal 0, AgentPendingSync.count
  end

  test "ProcessOrderService: a failed or not-ready tenant provision is recorded" do
    service = ProcessOrderService.new(Order.new)
    service.project = @project
    service.region = @region
    fake_ok = Struct.new(:perform, :errors, :volume_clones).new(true, [], nil)
    run = ->(agent_new) do
      service.event = EventLog.create!(locale: "order.provision", event_code: "0a3af01a3384fa10", status: "pending")
      Agent::Client.stub(:new, agent_new) do
        ProvisionServices::SftpProvisioner.stub(:new, ->(*) { fake_ok }) do
          ProjectServices::MetadataSshKeys.stub(:new, ->(*) { fake_ok }) do
            DeployServices::DeployProjectService.stub(:new, ->(*) { fake_ok }) do
              service.send(:finalize!)
            end
          end
        end
      end
    end

    run.call(->(*, **) { FakeAgentClient.new(provision_tenant!: false) })
    assert_equal 1, row("tenant").generation
    run.call(not_ready)
    assert_equal 2, row("tenant").generation
    run.call(->(*, **) { FakeAgentClient.new })
    assert_nil row("tenant")
  end

  test "firewall: records on false, on a rule-build failure, and clears on success" do
    Agent::Client.stub(:for_node, FakeAgentClient.new(put_firewall_rules: false)) { @node.update_iptable_config! }
    assert_equal 1, row("firewall", project: nil, node: @node).generation

    @node.stub(:iptable_rules, -> { raise ActiveRecord::StatementInvalid, "boom" }) do
      ExceptionAlertService.stub(:new, ->(*) { Struct.new(:perform).new(nil) }) do
        Agent::Client.stub(:for_node, FakeAgentClient.new) { @node.update_iptable_config! }
      end
    end
    r = row("firewall", project: nil, node: @node)
    assert_equal 2, r.generation
    assert_match "could not be built", r.last_error

    Agent::Client.stub(:for_node, FakeAgentClient.new) { assert @node.update_iptable_config! }
    assert_nil row("firewall", project: nil, node: @node)
  end

  test "firewall: record_drop: false neither records nor clears" do
    Agent::Client.stub(:for_node, FakeAgentClient.new(put_firewall_rules: false)) { @node.update_iptable_config!(record_drop: false) }
    assert_equal 0, AgentPendingSync.count
  end

  test "ReloadIptableWorker records a firewall drop from its rescues" do
    @node.stub(:update_iptable_config!, -> { raise Errno::ECONNREFUSED }) do
      GlobalID::Locator.stub(:locate, @node) do
        NodeWorkers::ReloadIptableWorker.new.perform(@node.global_id.to_s)
      end
    end
    assert row("firewall", project: nil, node: @node)
  end

  # --- tenant registry ------------------------------------------------------------

  test "deleting? is true once tombstoned, or when the Project row is gone" do
    refute Agent::TenantRegistry.deleting?(@project.id)
    assert Agent::TenantRegistry.deleting?(987_654)
    Agent::TenantRegistry.tombstone!(@project.id, [@region.id])
    assert Agent::TenantRegistry.deleting?(@project.id)
  end

  test "provisioned! never clears a tombstone" do
    Agent::TenantRegistry.tombstone!(@project.id, [@region.id])
    Agent::TenantRegistry.provisioned!(@project.id, @region.id)
    assert AgentTenant.find_by(project_id: @project.id, region_id: @region.id).deleting_at
  end

  test "the backfill registers each project in its container, sftp and network regions" do
    AgentTenant.delete_all
    require Rails.root.join("db/migrate/20261007000002_create_agent_tenants.rb").to_s
    migration = CreateAgentTenants.new
    migration.define_singleton_method(:create_table) { |*, **| }
    migration.define_singleton_method(:add_index) { |*, **| }
    ActiveRecord::Migration.suppress_messages { migration.up }
    assert AgentTenant.exists?(project_id: @project.id, region_id: @region.id)
    assert AgentTenant.exists?(project_id: deployments(:user_project_test).id, region_id: @region.id),
      "a project with only an sftp container is registered too"
  end
end
