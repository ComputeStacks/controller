require "test_helper"
require "minitest/mock"

class Deployment::ContainerTest < ActiveSupport::TestCase
  test "can list all containers" do
    c = Deployment::Container.first
    u = c.user

    assert_includes Deployment::Container.find_all_for(u), c
  end

  test "collaborators can view containers too" do
    c = Deployment::Container.first
    u = User.where.not(id: c.user.id).first

    refute_includes Deployment::Container.find_all_for(u), c

    c.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: u

    refute_includes Deployment::Container.find_all_for(u), c

    c.deployment.deployment_collaborators.first.update active: true

    assert_includes Deployment::Container.find_all_for(u), c

    c.deployment.deployment_collaborators.delete_all
  end

  test "latest_image? skips Docker for an offline or maintenance node" do
    c = Deployment::Container.first
    boom = ->(*) { flunk "Docker should not be called" }
    Docker::Container.stub(:get, boom) do
      c.node.disconnected = true
      assert c.latest_image?
      c.node.disconnected = false
      c.node.stub(:maintenance, true) { assert c.latest_image? }
    end
  end

  test "latest_image? reports true, not ok, when the image lookup errors" do
    c = Deployment::Container.first
    c.node.disconnected = false
    c.node.stub(:maintenance, false) do
      fake = Struct.new(:info).new({"Image" => "sha256:abc", "Config" => {"Image" => "repo:tag"}})
      Docker::Container.stub(:get, fake) do
        Docker::Image.stub(:get, ->(*) { raise "connection reset" }) do
          assert_equal [true, false], c.latest_image_check
          assert c.latest_image?
        end
      end
    end
  end

  test "latest_image? compares the running image's tags" do
    c = Deployment::Container.first
    c.node.disconnected = false
    c.node.stub(:maintenance, false) do
      fake = Struct.new(:info).new({"Image" => "sha256:abc", "Config" => {"Image" => "repo:tag"}})
      Docker::Container.stub(:get, fake) do
        Docker::Image.stub(:get, Struct.new(:info).new({"RepoTags" => ["repo:other"]})) do
          assert_equal [false, true], c.latest_image_check
        end
      end
    end
  end

  test "latest_image? returns a pre-set result without asking Docker" do
    c = Deployment::Container.first
    c.latest_image_result = false
    Docker::Container.stub(:get, ->(*) { flunk "Docker should not be called" }) do
      refute c.latest_image?
    end
  end

  # Stand-in for a container in a listing: records whether it was live-checked.
  FakeListed = Struct.new(:node_id, :check, :latest_image_result, :checked) do
    def latest_image_check
      self.checked = true
      check
    end
  end

  test "resolve_latest_images stops asking a node once it fails to answer" do
    failing = Array.new(3) { FakeListed.new(1, [true, false]) }
    healthy = FakeListed.new(2, [false, true])
    Deployment::Container.resolve_latest_images(failing + [healthy])

    assert failing.first.checked
    refute failing[1].checked
    refute failing[2].checked
    assert(failing.all? { |c| c.latest_image_result == true })
    assert healthy.checked
    assert_equal false, healthy.latest_image_result
  end

  test "resolve_latest_images skips live checks once the budget is spent" do
    listed = Array.new(2) { FakeListed.new(1, [false, true]) }
    Deployment::Container.resolve_latest_images(listed, budget: 0)

    refute(listed.any?(&:checked))
    assert(listed.all? { |c| c.latest_image_result == true })
  end
end
