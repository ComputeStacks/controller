require "test_helper"

class Admin::ContainerImages::VolumeParams::CascadeControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    @image = container_images(:custom)
    @param = container_image_volume_params(:custom_files)
    ImageWorkers::CascadeVolumeChangeWorker.clear
  end

  test "admin can apply an existing volume param to deployed services" do
    sign_in users(:admin)

    post "/admin/container_images/#{@image.id}/volume_params/#{@param.id}/cascade"

    assert_response :redirect
    assert_equal 1, ImageWorkers::CascadeVolumeChangeWorker.jobs.size

    event = EventLog.find(ImageWorkers::CascadeVolumeChangeWorker.jobs.first["args"][1])
    assert_equal [@param.id, event.id], ImageWorkers::CascadeVolumeChangeWorker.jobs.first["args"]
    assert_equal "image.cascade_volume", event.locale
    assert_equal "pending", event.status
    assert_includes event.container_images, @image
  end

  test "non admin cannot apply a volume param to deployed services" do
    sign_in users(:user)

    post "/admin/container_images/#{@image.id}/volume_params/#{@param.id}/cascade"

    assert_response :redirect
    assert_empty ImageWorkers::CascadeVolumeChangeWorker.jobs
  end

  test "mounted reference volumes are refused" do
    sign_in users(:admin)

    image = container_images(:nginx_shared)
    param = container_image_volume_params(:nginx_mounted)

    post "/admin/container_images/#{image.id}/volume_params/#{param.id}/cascade"

    assert_response :redirect
    assert_empty ImageWorkers::CascadeVolumeChangeWorker.jobs
    assert_match(/Mounted volumes/, flash[:alert])
  end

  test "unknown volume param is refused" do
    sign_in users(:admin)

    post "/admin/container_images/#{@image.id}/volume_params/0/cascade"

    assert_response :redirect
    assert_empty ImageWorkers::CascadeVolumeChangeWorker.jobs
  end
end
