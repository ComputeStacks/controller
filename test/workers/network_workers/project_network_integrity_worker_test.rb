require "test_helper"
require "minitest/mock"

class NetworkWorkers::ProjectNetworkIntegrityWorkerTest < ActiveSupport::TestCase
  W = NetworkWorkers::ProjectNetworkIntegrityWorker

  setup do
    @project = deployments(:project_test)
    @other_project = deployments(:user_project_test)
    @network = networks(:test_project_net)
    @other_network = networks(:user_test_project_net)
    # A clean, settled install: both fixture projects own an active network, and every row
    # is older than the grace period.
    @network.update_columns(deployment_id: @project.id, active: true, updated_at: 1.hour.ago)
    @other_network.update_columns(deployment_id: @other_project.id, active: true, updated_at: 1.hour.ago)
    Deployment::Container.update_all(created_at: 1.hour.ago)
    Deployment::Sftp.update_all(created_at: 1.hour.ago)
    SystemEvent.where(event_code: [W::MISSING_NETWORK_EVENT_CODE, W::INACTIVE_NETWORK_EVENT_CODE, W::MISSING_IP_EVENT_CODE]).delete_all
  end

  test "silent when everything is in place" do
    assert_no_difference -> { SystemEvent.count } do
      W.new.perform
    end
  end

  test "reports a project with active containers and no network" do
    @network.update_columns(deployment_id: nil)

    W.new.perform

    se = SystemEvent.find_by!(event_code: W::MISSING_NETWORK_EVENT_CODE)
    assert_equal "warn", se.log_level
    assert_equal 1, se.data[:total]
    assert_match @project.name, se.data[:items].join
    assert_match "no private network", se.message
  end

  test "reports a project whose only active container is SFTP" do
    @network.update_columns(deployment_id: nil)
    Deployment::Container.joins(:service).where(deployment_container_services: {deployment_id: @project.id}).update_all(req_state: "stopped")

    W.new.perform

    assert_match @project.name, SystemEvent.find_by!(event_code: W::MISSING_NETWORK_EVENT_CODE).data[:items].join
  end

  test "reports a bound network that is not active" do
    @network.update_columns(active: false)

    W.new.perform

    se = SystemEvent.find_by!(event_code: W::INACTIVE_NETWORK_EVENT_CODE)
    assert_equal 1, se.data[:total]
    assert_match @network.name, se.data[:items].join
    assert_nil SystemEvent.find_by(event_code: W::MISSING_NETWORK_EVENT_CODE)
  end

  test "reports active containers and SFTP containers with no IP" do
    container = deployment_containers(:wordpress_1)
    sftp = deployment_sftp(:project_test_testone)
    container.ip_address.destroy!
    sftp.ip_address.destroy!

    W.new.perform

    se = SystemEvent.find_by!(event_code: W::MISSING_IP_EVENT_CODE)
    assert_equal 2, se.data[:total]
    assert_match container.name, se.data[:items].join
    assert_match sftp.name, se.data[:items].join
  end

  test "a stopped container with no IP is not reported" do
    container = deployment_containers(:wordpress_1)
    container.ip_address.destroy!
    container.update_columns(req_state: "stopped")

    W.new.perform

    assert_nil SystemEvent.find_by(event_code: W::MISSING_IP_EVENT_CODE)
  end

  test "ignores rows inside the grace period" do
    @network.update_columns(deployment_id: nil)
    @other_network.update_columns(active: false, updated_at: Time.current)
    deployment_containers(:wordpress_1).ip_address.destroy!
    Deployment::Container.update_all(created_at: Time.current)
    Deployment::Sftp.update_all(created_at: Time.current)

    assert_no_difference -> { SystemEvent.count } do
      W.new.perform
    end
  end

  test "clustered regions are only checked for missing IPs" do
    regions(:regionone).update_columns(network_driver: "calico_docker")
    @network.update_columns(deployment_id: nil)
    @other_network.update_columns(active: false)
    deployment_containers(:wordpress_1).ip_address.destroy!

    W.new.perform

    assert_nil SystemEvent.find_by(event_code: W::MISSING_NETWORK_EVENT_CODE)
    assert_nil SystemEvent.find_by(event_code: W::INACTIVE_NETWORK_EVENT_CODE)
    refute_nil SystemEvent.find_by(event_code: W::MISSING_IP_EVENT_CODE)
  end

  test "a second run updates the same SystemEvent" do
    container = deployment_containers(:wordpress_1)
    container.ip_address.destroy!

    W.new.perform
    se = SystemEvent.find_by!(event_code: W::MISSING_IP_EVENT_CODE)
    first_seen = se.data[:first_seen]

    deployment_containers(:mysql_1).ip_address.destroy!
    assert_no_difference -> { SystemEvent.count } do
      W.new.perform
    end

    se.reload
    assert_equal 2, se.data[:count]
    assert_equal 2, se.data[:total], "the latest findings replace the previous ones"
    assert_equal first_seen.to_i, se.data[:first_seen].to_i
    assert se.data[:last_seen] >= first_seen
  end

  test "never raises" do
    reported = []
    alert = Object.new
    alert.define_singleton_method(:perform) { true }
    Region.stub(:where, ->(*) { raise "boom" }) do
      ExceptionAlertService.stub(:new, ->(e, code) { reported << [e.message, code]; alert }) do
        assert_nothing_raised { W.new.perform }
      end
    end
    assert_includes reported, ["boom", W::ERROR_EVENT_CODE]
  end
end
