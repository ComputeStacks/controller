# Container Image Collaborators
class Api::ContainerImages::CollaboratorsController < Api::ContainerImages::BaseController

  before_action :verify_admin
  before_action :find_collab, only: %i[show destroy]

  ##
  # List All Collaborators
  #
  # `GET /api/container_images/{container-image-id}/collaborators`
  #
  # **OAuth Authorization Required**: `images_read`
  #
  #   * `collaborations`: Array
  #       * `id`: Integer
  #       * `resource_owner`: Object
  #           * `id`: Integer
  #           * `email`: String
  #           * `full_name`: String
  #
  def index
    @collaborators = @image.container_image_collaborators.sorted
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/collaborations/index_type' }
    end
  end

  ##
  # View Collaborator
  #
  # `GET /api/container_images/{container-image-id}/collaborators/{id}`
  #
  # **OAuth Authorization Required**: `images_read`
  #
  # * `collaboration`: Object
  #     * `id`: String
  #     * `image`: Object
  #         * `id`: Integer
  #         * `name`: String
  # * `resource_owner`: Object
  #     * `id`: Integer
  #     * `email`: String
  #     * `full_name`: String
  #
  def show
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/collaborations/show' }
    end
  end

  ##
  # Create Collaborator Request
  #
  # `POST /api/container_images/{container-image-id}/collaborators`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `collaborator`: Object
  #     * `user_email`: String
  #
  def create
    @collab = @image.container_image_collaborators.new user_email: collaborator_params[:user_email], current_user: current_user
    return api_obj_error(@collab.errors.full_messages) unless @collab.save
    render action: :show, status: :created
  end

  ##
  # Remove Collaborator
  #
  # `DELETE /api/container_images/{container-image-id}/collaborators/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    return api_obj_error(@collab.errors.full_messages) unless @collab.destroy
    render head: :accepted
  end

  private

  # Only allow resource owner and admin to manage collaborators
  def verify_admin
    unless @image.can_administer? current_user
      render head: :unauthorized
    end
  end

  def find_collab
    @collab = @image.container_image_collaborators.find_by id: params[:id]
    return api_obj_missing if @collab.nil?
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:collaborator).permit(:user_email)
  end

end
