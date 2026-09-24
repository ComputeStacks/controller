##
# Retroactively apply an image volume parameter to existing deployed services.
class Admin::ContainerImages::VolumeParams::CascadeController < Admin::ContainerImages::BaseController
  before_action :find_volume

  ##
  # Apply to existing services
  #
  # `POST /admin/container_images/{image-id}/volume_params/{id}/cascade`
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
