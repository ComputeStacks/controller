class ContainerImages::BaseController < AuthController

  before_action :find_image

  private

  def find_image
    @container = ContainerImage.find_for_edit(current_user, id: params[:container_image_id])
    if @container.nil?
      redirect_to "/container_images", alert: I18n.t('crud.unknown', resource: I18n.t('obj.container'))
      return false
    end
    @container.current_user = current_user
    @image = @container # @container is deprecated
  end

end
