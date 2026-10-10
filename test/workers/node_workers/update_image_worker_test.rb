require "test_helper"
require "minitest/mock"

class NodeWorkers::UpdateImageWorkerTest < ActiveSupport::TestCase
  test "refreshes bastion image status, and a failure there does not stop the prune" do
    node = nodes(:testone)
    pruned = false
    status_checked = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |path, *|
      pruned = true if path.start_with?("/images/prune")
      "{}"
    end
    # The worker reloads the node via Node.online.find_by; hand it ours so its client is faked.
    node.define_singleton_method(:client) { |*| fake_client }
    online = Object.new
    online.define_singleton_method(:find_by) { |*| node }
    puller = Struct.new(:raw_image) { def perform = true }

    Node.stub(:online, online) do
      ContainerImage.stub(:is_public, []) do
        NodeServices::PullImageService.stub(:new, ->(*) { puller.new }) do
          Docker::Image.stub(:get, ->(*) { raise Docker::Error::TimeoutError, "read timeout" }) do
            real_new = NodeServices::BastionImageStatusService.method(:new)
            NodeServices::BastionImageStatusService.stub(:new, ->(n) { status_checked = n; real_new.call(n) }) do
              NodeWorkers::UpdateImageWorker.new.perform(node.id)
            end
          end
        end
      end
    end
    assert_equal node, status_checked
    assert pruned
  end
end
