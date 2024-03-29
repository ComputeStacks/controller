##
# # Pull Container Image
class Admin::ContainerImages::PullController < Admin::ContainerImages::BaseController

  ##
  # Manually Pull Container Image
  #
  # `POST /admin/container_images/{id}/pull`
  #
  def create
    ImageWorkers::PullImageWorker.perform_async nil, @image.global_id
    redirect_to "/admin/container_images/#{@image.id}", notice: "#{@image.label} pull will be performed shortly."
  end

end
