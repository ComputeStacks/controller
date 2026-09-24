##
# Retroactively apply an image volume parameter to existing deployed services.
#
# Admin-only -- the authorization decision lives in ImageServices::CascadeVolumeService,
# because cascading mutates other users' running services.
class ContainerImages::VolumeParams::CascadeController < ContainerImages::BaseController
  before_action :find_volume

  ##
  # Apply to existing services
  #
  # `POST /container_images/{image-id}/volume_params/{id}/cascade`
  #
  def create
    cascade = ImageServices::CascadeVolumeService.new(@volume, current_user, request.remote_ip)
    event = cascade.perform
    if event
      redirect_to helpers.container_image_path(@image),
        success: "Applying this volume to existing services (event ##{event.id}). Containers mount it on their next rebuild."
    else
      redirect_to helpers.container_image_path(@image),
        alert: "Unable to apply this volume to existing services: #{cascade.errors.join(" ")}"
    end
  end

  private

  def find_volume
    @volume = @image.volumes.find_by(id: params[:volume_param_id])
    if @volume.nil?
      redirect_to helpers.container_image_path(@image), alert: "Volume not found."
      return false
    end
    @volume.current_user = current_user
  end
end
