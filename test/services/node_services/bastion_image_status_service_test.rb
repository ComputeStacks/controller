require "test_helper"
require "minitest/mock"

class NodeServices::BastionImageStatusServiceTest < ActiveSupport::TestCase
  FakeImage = Struct.new(:id)
  FakeContainer = Struct.new(:info)

  setup do
    @node = nodes(:testone)
    @bastion = Deployment::Sftp.find_by!(name: "distracted-franklin195")
    @other = Deployment::Sftp.find_by!(name: "photo-franklin195")
    [@bastion, @other].each { |b| b.update_column(:on_latest_image, true) }
  end

  def listing(map)
    map.map { |name, image_id| FakeContainer.new({"Names" => ["/#{name}"], "ImageID" => image_id}) }
  end

  def with_docker(image: FakeImage.new("sha256:new"), containers: [])
    image_get = image.respond_to?(:call) ? image : ->(*) { image }
    all = containers.respond_to?(:call) ? containers : ->(*) { containers }
    Docker::Image.stub(:get, image_get) do
      Docker::Container.stub(:all, all) { yield }
    end
  end

  test "marks a bastion running the configured image as latest" do
    @bastion.update_column(:on_latest_image, false)
    with_docker(containers: listing(@bastion.name => "sha256:new")) do
      assert NodeServices::BastionImageStatusService.new(@node).perform
    end
    assert @bastion.reload.on_latest_image
  end

  test "marks a bastion running a different image as not latest" do
    with_docker(containers: listing(@bastion.name => "sha256:old", @other.name => "sha256:new")) do
      assert NodeServices::BastionImageStatusService.new(@node).perform
    end
    refute @bastion.reload.on_latest_image
    assert @other.reload.on_latest_image
  end

  test "leaves a bastion absent from the node unchanged" do
    @other.update_column(:on_latest_image, false)
    with_docker(containers: listing(@bastion.name => "sha256:old")) do
      NodeServices::BastionImageStatusService.new(@node).perform
    end
    refute @other.reload.on_latest_image
  end

  test "changes nothing when the configured image is not on the node" do
    with_docker(image: ->(*) { raise Docker::Error::NotFoundError, "no such image" },
      containers: listing(@bastion.name => "sha256:old")) do
      refute NodeServices::BastionImageStatusService.new(@node).perform
    end
    assert @bastion.reload.on_latest_image
  end

  test "changes nothing when listing containers fails" do
    with_docker(containers: ->(*) { raise Docker::Error::TimeoutError, "read timeout" }) do
      refute NodeServices::BastionImageStatusService.new(@node).perform
    end
    assert @bastion.reload.on_latest_image
  end

  test "makes no Docker calls for an offline node" do
    @node.update_column(:disconnected, true)
    boom = ->(*) { flunk "Docker should not be called" }
    with_docker(image: boom, containers: boom) do
      refute NodeServices::BastionImageStatusService.new(@node.reload).perform
    end
  end
end
