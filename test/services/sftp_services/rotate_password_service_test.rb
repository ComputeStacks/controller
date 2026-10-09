require "test_helper"
require "minitest/mock"

class SftpServices::RotatePasswordServiceTest < ActiveSupport::TestCase
  setup do
    @sftp = deployment_sftp(:project_test_testone)
    @audit = Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "updated")
    @old_password = @sftp.password
  end

  # Stands in for PowerCycleContainerService when a test needs a specific outcome.
  FakePowerCycle = Struct.new(:result, :event, :errors, :callback_url, :callback_auth, :outcome) do
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

  test "passes the callback to the rebuild event" do
    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    service.callback_url = "https://integration.example.com/api/webhooks/task/42"
    service.callback_auth = "Bearer abc123"
    assert service.perform, service.errors.join(" ")

    assert_equal "https://integration.example.com/api/webhooks/task/42", service.event.labels["callback_url"]
    assert_equal "Bearer abc123", service.event.labels["callback_auth"]
  end

  test "refuses when the node is in maintenance" do
    @sftp.node.update!(maintenance_requested: true)
    @sftp.node.reload # `maintenance` is generated; read it back
    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    refute service.perform
    assert_match(/in maintenance/, service.errors.join)
    assert_equal "node_maintenance", service.error_code
    assert_equal @old_password, @sftp.reload.password
  end

  test "refuses with node_offline when the node is offline or missing" do
    @sftp.node.update_columns(disconnected: true)
    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    refute service.perform
    assert_equal "node_offline", service.error_code

    @sftp.update_columns(node_id: nil)
    service = SftpServices::RotatePasswordService.new(@sftp.reload, @audit)
    refute service.perform
    assert_equal "node_offline", service.error_code
  end

  test "a rebuild refused because the node went offline carries node_offline" do
    fake = FakePowerCycle.new(false, nil, [], nil, nil, :refused_offline)
    PowerCycleContainerService.stub(:new, fake) do
      service = SftpServices::RotatePasswordService.new(@sftp, @audit)
      refute service.perform
      assert_equal "node_offline", service.error_code
    end
  end

  test "other refusals carry no code" do
    busy = EventLog.create!(locale: "container.restart", status: "running", event_code: "d611b2bbf50bd48c")
    busy.sftp_containers << @sftp
    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    refute service.perform
    assert_nil service.error_code
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

  # A rebuild refused inside PowerCycle (a race with another action) still creates its
  # event, so the caller's callback reports the cancellation.
  test "a rebuild canceled after its event exists carries the callback" do
    busy = EventLog.create!(locale: "container.rebuild", status: "running", event_code: "14bbe1dc184afba0")
    busy.sftp_containers << @sftp

    service = SftpServices::RotatePasswordService.new(@sftp, @audit)
    service.callback_url = "https://integration.example.com/api/webhooks/task/42"
    service.stub(:preconditions_met?, true) do
      refute service.perform
    end
    assert_equal @old_password, @sftp.reload.password

    canceled = @sftp.event_logs.where.not(id: busy.id).sole
    assert canceled.cancelled?
    assert_equal "https://integration.example.com/api/webhooks/task/42", canceled.labels["callback_url"]
  end

  test "restores the password the row held at write time, not a stale copy" do
    stale = Deployment::Sftp.find(@sftp.id)
    @sftp.update!(password: "set-by-a-concurrent-rotation")
    fake = FakePowerCycle.new(false, nil, ["Fatal error setting up job."])

    service = SftpServices::RotatePasswordService.new(stale, @audit)
    PowerCycleContainerService.stub(:new, fake) do
      refute service.perform
    end
    assert_equal "set-by-a-concurrent-rotation", @sftp.reload.password
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
