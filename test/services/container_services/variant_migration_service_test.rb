require "test_helper"
require "minitest/mock"

class ContainerServices::VariantMigrationServiceTest < ActiveSupport::TestCase
  setup do
    @service = deployment_container_services(:wordpress)
    @audit = Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "updated")
    @migration = ContainerServices::VariantMigrationService.new(@service, @audit, @service.image_variant)
  end

  def refreshes
    refreshed = []
    ProjectWorkers::RefreshMetadataPhpWorker.stub(:perform_async, ->(*args) { refreshed << args }) do
      yield
    end
    refreshed
  end

  test "a completed migration refreshes metadata and bastion PHP" do
    @migration.container = @service.containers.first
    refreshed = refreshes do
      @migration.stub(:pre_migration!, true) do
        @migration.stub(:rebuild!, true) do
          @migration.stub(:post_migration!, true) do
            assert @migration.perform
          end
        end
      end
    end
    assert_equal [[@service.deployment.id, @audit.id]], refreshed
  end

  # Every failure path restores the previous variant, which the metadata already describes.
  # Refreshing would also bury the failed migration under a newer project event.
  test "a failed migration leaves metadata alone" do
    refreshed = refreshes do
      @migration.stub(:valid?, false) do
        refute @migration.perform
      end
    end
    assert_empty refreshed
  end
end
