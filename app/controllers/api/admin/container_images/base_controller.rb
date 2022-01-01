class Api::Admin::ContainerImages::BaseController < Api::Admin::ApplicationController

  before_action :find_image

  private

  def find_image
    @image = ContainerImage.find params[:container_image_id]
    @image.current_user = current_user
  end

end
