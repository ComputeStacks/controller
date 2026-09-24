class Api::ContainerImages::BaseController < Api::ApplicationController
  api_scope read: [:public, :images_read], write: :images_write

  before_action :find_image, only: %i[index show]
  before_action :find_protected_image, only: %i[create update destroy]

  private

  def find_image
    @image = if current_user # allow publicly scoped oauth to view public images.
      ContainerImage.find_for current_user, id: params[:container_image_id]
    else
      ContainerImage.where(id: params[:container_image_id], active: true, user: nil).first
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
