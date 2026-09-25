require "test_helper"
require "minitest/mock"

class SftpServices::RotatePasswordServiceTest < ActiveSupport::TestCase
  setup do
    @sftp = deployment_sftp(:project_test_testone)
    @audit = Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "updated")
    @old_password = @sftp.password
  end

  # Stands in for PowerCycleContainerService when a test needs a specific outcome.
  FakePowerCycle = Struct.new(:result, :event, :errors) do
    def perform
      result
    end
  end

  test "rotates the password and records it on the rebuild event" do
    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    assert service.perform, service.errors.join(" ")
    assert_empty service.errors

    @sftp.reload
    refute_equal @old_password, @sftp.password
    assert @sftp.password.present?

    assert service.event
    assert service.event.pending?
    assert_equal "container.rebuild", service.event.locale
    assert_includes service.event.sftp_containers, @sftp
    assert service.event.event_details.where(data: "SSH password rotated.").exists?
    refute service.event.event_details.where("data LIKE ?", "%#{@sftp.password}%").exists?
  end

  test "refuses when the node is offline" do
    @sftp.node.update!(maintenance: true)
    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    refute service.perform
    refute_empty service.errors
    assert_equal @old_password, @sftp.reload.password
  end

  test "refuses when another action is in progress" do
    busy = EventLog.create!(locale: "container.restart", status: "running", event_code: "d611b2bbf50bd48c")
    busy.sftp_containers << @sftp

    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    refute service.perform
    assert_equal ["Another action is in progress on this SSH container; try again shortly."], service.errors
    assert_equal @old_password, @sftp.reload.password
  end

  test "refuses when the container is being trashed" do
    @sftp.update_column(:to_trash, true)
    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    refute service.perform
    refute_empty service.errors
    assert_equal @old_password, @sftp.reload.password
  end

  test "restores the old password when the rebuild is cancelled" do
    cancelled = EventLog.create!(locale: "container.rebuild", status: "cancelled", event_code: "14bbe1dc184afba0")
    fake = FakePowerCycle.new(true, cancelled, [])

    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    PowerCycleContainerService.stub(:new, fake) do
      refute service.perform
    end
    assert_equal ["Unable to rebuild the SSH container."], service.errors
    assert_nil service.event
    assert_equal @old_password, @sftp.reload.password
  end

  test "restores the old password and surfaces errors when the rebuild is refused" do
    fake = FakePowerCycle.new(false, nil, ["Fatal error setting up job."])

    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    PowerCycleContainerService.stub(:new, fake) do
      refute service.perform
    end
    assert_equal ["Fatal error setting up job."], service.errors
    assert_equal @old_password, @sftp.reload.password
  end
end
