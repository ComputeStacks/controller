require "test_helper"
require "minitest/mock"

class SftpServices::SelectPhpVersionServiceTest < ActiveSupport::TestCase
  setup do
    @sftp = deployment_sftp(:project_test_testone)
    @audit = Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "updated")
  end

  test "records an event and execs select_php_version in the bastion" do
    calls = []
    ContainerWorkers::ContainerExecWorker.stub(:perform_async, ->(*args) { calls << args }) do
      service = SftpServices::SelectPhpVersionService.new(@sftp, @audit)
      assert service.perform
      assert_equal "sftp.select_php_version", service.event.locale
      assert_includes service.event.sftp_containers, @sftp
      assert_equal [[@sftp.global_id, service.event.global_id, %w[/usr/bin/ruby /usr/local/bin/select_php_version]]], calls
    end
  end

  test "rejects a non-sftp container" do
    service = SftpServices::SelectPhpVersionService.new(deployment_containers(:pma_1), @audit)
    refute service.perform
    assert_nil service.event
  end
end
