##
# # Pull Container Image
class Api::Admin::ContainerImages::PullController < Api::Admin::ContainerImages::BaseController

  ##
  # Manually Pull Container Image
  #
  # `POST /api/admin/container_images/{id}/pull`
  #
  def create
    ImageWorkers::PullImageWorker.perform_async nil, @image.to_global_id.to_s
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

end
