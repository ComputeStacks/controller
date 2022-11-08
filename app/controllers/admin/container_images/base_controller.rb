class Admin::ContainerImages::BaseController < Admin::ApplicationController

  before_action :find_image

  private

  def find_image
    @container = ContainerImage.find_by(id: params[:container_image_id])
    if @container.nil?
      redirect_to "/admin/container_images", alert: I18n.t('crud.unknown', resource: I18n.t('obj.image'))
      return false
    end
    @container.current_user = current_user
    @image = @container # @container is deprecated
  end

end
