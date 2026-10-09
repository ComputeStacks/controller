require "test_helper"
require "webmock"
require "minitest/mock"

##
# §11 additions to Agent::Client: the tenant registry write on provision (incl. the
# self-heal), put_managed(self_heal: false), .for_project_id and .raising_transport_errors.
class Agent::ClientRegistryTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!
    @project = deployments(:project_test)
    @project.update_columns(consul_auth_key: "customer-bearer-key")
    @node = nodes(:testone)
    @node.update_columns(primary_ip: "10.50.0.9")
    @node.reload
    @region = regions(:regionone)
    @base = "http://10.50.0.9:8500"
    @tenant = "#{@base}/v1/admin/tenants/#{@project.id}"
    @managed = "#{@base}/v1/admin/projects/#{@project.id}/managed/metadata"
    AgentTenant.delete_all
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  test "a successful provision writes the registry row" do
    stub_request(:put, @tenant).to_return(status: 200)
    assert Agent::Client.new(@project, region: @region).provision_tenant!
    row = AgentTenant.find_by(project_id: @project.id, region_id: @region.id)
    assert row&.provisioned_at
    assert_nil row.deleting_at
  end

  test "a failed provision writes no registry row" do
    stub_request(:put, @tenant).to_return(status: 500)
    refute Agent::Client.new(@project, region: @region).provision_tenant!
    assert_equal 0, AgentTenant.count
  end

  test "the self-heal provision inside put_managed writes the registry row" do
    stub_request(:put, @managed).to_return({status: 404}, {status: 200})
    stub_request(:put, @tenant).to_return(status: 200)
    assert Agent::Client.new(@project, region: @region).put_managed("metadata", "{}")
    assert AgentTenant.exists?(project_id: @project.id, region_id: @region.id)
  end

  test "put_managed(self_heal: false) never provisions: it records a pending tenant sync" do
    stub_request(:put, @managed).to_return(status: 404)
    tenant = stub_request(:put, @tenant)
    refute Agent::Client.new(@project, region: @region).put_managed("metadata", "{}", self_heal: false)
    assert_not_requested tenant
    assert_equal ["tenant"], AgentPendingSync.where(project_id: @project.id, region_id: @region.id).pluck(:kind)
  end

  test "for_project_id deprovisions a project whose row is gone" do
    stub = stub_request(:delete, "#{@base}/v1/admin/tenants/424242").to_return(status: 200)
    assert Agent::Client.for_project_id(424242, region: @region).deprovision_tenant!
    assert_requested stub
  end

  test "raising_transport_errors re-raises transport errors only inside the block" do
    stub_request(:put, @tenant).to_raise(HTTP::ConnectionError)
    client = Agent::Client.new(@project, region: @region)
    assert_raises(HTTP::ConnectionError) do
      Agent::Client.raising_transport_errors { client.provision_tenant! }
    end
    ExceptionAlertService.stub(:new, ->(*) { Struct.new(:perform).new(nil) }) do
      assert_equal false, client.provision_tenant!
    end
  end
end
