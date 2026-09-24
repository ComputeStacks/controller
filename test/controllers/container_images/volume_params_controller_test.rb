require "test_helper"

class ContainerImages::VolumeParamsControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    @image = container_images(:custom)
    ImageWorkers::CascadeVolumeChangeWorker.clear
  end

  # The non-admin controller renders the same form (with the same cascade checkbox) as the
  # admin one, and `ContainerImageHelper#container_image_path` posts here whenever the form
  # was reached from the non-admin image list.
  test "unchecked cascade box does not cascade" do
    sign_in users(:admin)

    assert_difference "@image.volumes.count", 1 do
      post "/container_images/#{@image.id}/volume_params", params: {
        container_image_volume_param: {
          label: "extra",
          mount_path: "/mnt/extra",
          cascade_changes: "0"
        }
      }
    end
    assert_response :redirect
    assert_empty ImageWorkers::CascadeVolumeChangeWorker.jobs
  end

  test "checked cascade box cascades" do
    sign_in users(:admin)

    assert_difference "@image.volumes.count", 1 do
      post "/container_images/#{@image.id}/volume_params", params: {
        container_image_volume_param: {
          label: "extra",
          mount_path: "/mnt/extra",
          cascade_changes: "1"
        }
      }
    end
    assert_response :redirect
    assert_equal 1, ImageWorkers::CascadeVolumeChangeWorker.jobs.size

    param = @image.volumes.order(:id).last
    event = EventLog.find(ImageWorkers::CascadeVolumeChangeWorker.jobs.first["args"][1])
    assert_equal [param.id, event.id], ImageWorkers::CascadeVolumeChangeWorker.jobs.first["args"]
    assert_equal "image.cascade_volume", event.locale
    assert_includes event.container_images, @image
  end

  test "a non admin collaborator cannot cascade" do
    @image.container_image_collaborators.create! current_user: users(:admin), collaborator: users(:user)
    @image.container_image_collaborators.first.update! active: true

    sign_in users(:user)

    assert_difference "@image.volumes.count", 1 do
      post "/container_images/#{@image.id}/volume_params", params: {
        container_image_volume_param: {
          label: "extra",
          mount_path: "/mnt/extra",
          cascade_changes: "1"
        }
      }
    end
    assert_response :redirect
    assert_empty ImageWorkers::CascadeVolumeChangeWorker.jobs
  end
end
