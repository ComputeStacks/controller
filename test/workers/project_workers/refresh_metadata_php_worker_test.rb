require "test_helper"
require "minitest/mock"

class ProjectWorkers::RefreshMetadataPhpWorkerTest < ActiveSupport::TestCase
  setup do
    @project = deployments(:project_test)
    @audit = Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "updated")
  end

  def run_worker(metadata_pushed)
    selected = []
    fake_select = ->(container, _audit) { Struct.new(:perform).new(selected << container) }
    ProjectServices::StoreMetadata.stub(:new, ->(_) { Struct.new(:perform).new(metadata_pushed) }) do
      SftpServices::SelectPhpVersionService.stub(:new, fake_select) do
        ProjectWorkers::RefreshMetadataPhpWorker.new.perform(@project.id, @audit.id)
      end
    end
    selected
  end

  test "pushes metadata then reselects PHP on every bastion" do
    assert_equal @project.sftp_containers.to_a.sort_by(&:id), run_worker(true).sort_by(&:id)
  end

  test "skips a stopped bastion" do
    @project.sftp_containers.update_all(status: "stopped")
    assert_empty run_worker(true)
  end

  test "leaves bastions alone when the metadata push fails" do
    assert_empty run_worker(false)
  end
end
