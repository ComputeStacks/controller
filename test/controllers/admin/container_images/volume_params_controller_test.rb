require "test_helper"

class Admin::ContainerImages::VolumeParamsControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    @image = container_images(:custom)
    ImageWorkers::CascadeVolumeChangeWorker.clear
  end

  test "unchecked cascade box does not cascade" do
    sign_in users(:admin)

    assert_difference "@image.volumes.count", 1 do
      post "/admin/container_images/#{@image.id}/volume_params", params: {
        container_image_volume_param: {
          label: "extra",
          mount_path: "/mnt/extra",
          # this is what rails' check_box helper posts when the box is left unchecked
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
      post "/admin/container_images/#{@image.id}/volume_params", params: {
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
    assert_equal "pending", event.status
    assert_includes event.container_images, @image
  end

  test "non admin cannot reach the admin create action" do
    sign_in users(:user)

    post "/admin/container_images/#{@image.id}/volume_params", params: {
      container_image_volume_param: {
        label: "extra",
        mount_path: "/mnt/extra",
        cascade_changes: "1"
      }
    }
    assert_response :redirect
    assert_empty ImageWorkers::CascadeVolumeChangeWorker.jobs
  end
end
