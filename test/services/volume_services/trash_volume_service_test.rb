require "test_helper"
require "minitest/mock"

##
# PR3 teardown (path b): TrashVolumeService keeps the synchronous docker-driver destroy AND
# now issues a DELETE to the node's cs-agent, which self-enqueues the idempotent
# `volume.trash` task (borg repo teardown). The KV metadata cleanup is gone.
class VolumeServices::TrashVolumeServiceTest < ActiveSupport::TestCase
  class FakeVolumeClient
    def destroy = true

    def errors = []
  end

  class FakeAgentClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def delete_volume(project_id, name)
      @calls << [project_id, name]
      true
    end
  end

  setup do
    @volume = volumes(:mysql)
    @volume.update_columns(to_trash: true, trash_after: 1.hour.ago)
    @event = @volume.event_logs.create!(locale: "volume.trash", locale_keys: {}, status: "pending",
      event_code: "test-trash")
    @fake = FakeAgentClient.new
  end

  test "perform destroys the volume and DELETEs it on the agent for borg teardown" do
    volume_name = @volume.name
    project_id = @volume.agent_project_id.to_s

    @volume.stub(:volume_client, FakeVolumeClient.new) do
      Agent::Client.stub(:for_node, @fake) do
        assert VolumeServices::TrashVolumeService.new(@volume, @event).perform
      end
    end

    assert_equal [[project_id, volume_name]], @fake.calls
    assert @event.reload.success?
    refute Volume.exists?(id: @volume.id), "the volume row is removed after teardown"
  end
end
