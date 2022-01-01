class Api::ContainerImages::BaseController < Api::ApplicationController

  before_action only: %i[index show], unless: :current_user do
    doorkeeper_authorize! :public, :images_read
  end

  before_action -> { doorkeeper_authorize! :images_write }, only: %i[update create destroy], unless: :current_user

  before_action :find_image, only: %i[index show]
  before_action :find_protected_image, only: %i[create update destroy]

  private

  def find_image
    if current_user # allow publicly scoped oauth to view public images.
      @image = ContainerImage.find_for current_user, id: params[:container_image_id]
    else
      @image = ContainerImage.where(id: params[:container_image_id], active: true, user: nil).first
    end
    return api_obj_missing if @image.nil?
    @image.current_user = current_user if current_user
  end

  # For CRUD operations, require that the user be the owner.
  def find_protected_image
    @image = ContainerImage.find_for_edit(current_user, id: params[:container_image_id])
    return api_obj_missing if @image.nil?
    @image.current_user = current_user
  end

end
