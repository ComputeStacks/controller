##
# # Pull Container Image Variant
class Admin::ContainerImages::ImageVariants::PullController < Admin::ContainerImages::ImageVariants::BaseController

  ##
  # Manually Pull Container Image Variant
  #
  # `POST /admin/container_images/{container_image_id}/image_variants/{id]/pull`
  #
  def create
    ImageWorkers::PullImageWorker.perform_async nil, @variant.global_id
    redirect_to "/admin/container_images/#{@image.id}", notice: "#{@variant.label} pull will be performed shortly."
  end

end
