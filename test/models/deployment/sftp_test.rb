require "test_helper"
require "minitest/mock"

class Deployment::SftpTest < ActiveSupport::TestCase
  setup do
    @sftp = Deployment::Sftp.first
  end

  test "can retrieve sftp password" do
    assert_not_nil @sftp.password
  end

  test "can assign private ip address" do
    assert_not_nil @sftp.local_ip
  end

  test "has an internal port" do
    refute_nil @sftp.public_port
  end

  test "can generate docker config" do
    assert_kind_of Hash, @sftp.build_command
  end

  test "latest_image? reads the stored column without asking the node" do
    boom = ->(*) { flunk "Docker should not be called" }
    Docker::Container.stub(:get, boom) do
      Docker::Image.stub(:get, boom) do
        @sftp.update_column(:on_latest_image, false)
        refute @sftp.latest_image?
        @sftp.update_column(:on_latest_image, true)
        assert @sftp.latest_image?
      end
    end
  end

  test "a successful build resets on_latest_image" do
    @sftp.update_column(:on_latest_image, false)
    @sftp.stub(:build_command, {"name" => @sftp.name}) do
      Docker::Container.stub(:create, ->(*) { Docker::Container.send(:new, Docker.connection, "id" => "abc") }) do
        assert @sftp.build!(nil)
      end
    end
    assert @sftp.reload.on_latest_image
  end
end
