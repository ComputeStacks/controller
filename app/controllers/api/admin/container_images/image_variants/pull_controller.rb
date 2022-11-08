##
# # Pull Container Image Variant
class Api::Admin::ContainerImages::ImageVariants::PullController < Api::Admin::ContainerImages::ImageVariants::BaseController

  ##
  # Manually Pull Container Image Variant
  #
  # `POST /api/admin/container_images/{container_image_id}/image_variants/{id}/pull`
  #
  def create
    ImageWorkers::PullImageWorker.perform_async nil, @variant.to_global_id.to_s
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

end
