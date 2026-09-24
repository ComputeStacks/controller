require "test_helper"

class ContainerImages::VolumeParams::CascadeControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    @image = container_images(:custom)
    @param = container_image_volume_params(:custom_files)
    ImageWorkers::CascadeVolumeChangeWorker.clear
  end

  test "admin can apply an existing volume param to deployed services" do
    sign_in users(:admin)

    post "/container_images/#{@image.id}/volume_params/#{@param.id}/cascade"

    assert_response :redirect
    assert_equal 1, ImageWorkers::CascadeVolumeChangeWorker.jobs.size

    event = EventLog.find(ImageWorkers::CascadeVolumeChangeWorker.jobs.first["args"][1])
    assert_equal [@param.id, event.id], ImageWorkers::CascadeVolumeChangeWorker.jobs.first["args"]
    assert_includes event.container_images, @image
  end

  # An image collaborator can edit the image, and therefore reach this controller, but must
  # not be able to touch other customers' running services.
  test "non admin collaborator cannot apply a volume param to deployed services" do
    @image.container_image_collaborators.create! current_user: users(:admin), collaborator: users(:user)
    @image.container_image_collaborators.first.update! active: true

    sign_in users(:user)

    post "/container_images/#{@image.id}/volume_params/#{@param.id}/cascade"

    assert_response :redirect
    assert_empty ImageWorkers::CascadeVolumeChangeWorker.jobs
    assert_match(/administrators/, flash[:alert])
  end
end
