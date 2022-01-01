# Container Registry Collaborators
class Api::Admin::ContainerRegistry::CollaboratorsController < Api::Admin::ContainerRegistry::BaseController

  before_action :find_collab, only: %i[show destroy]

  ##
  # List All Collaborators
  #
  # `GET /api/admin/container_registry/{container-registry-id}/collaborators`
  #
  #   * `collaborations`: Array
  #       * `id`: Integer
  #       * `resource_owner`: Object
  #           * `id`: Integer
  #           * `email`: String
  #           * `full_name`: String
  #
  def index
    @collaborators = @registry.container_registry_collaborators
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/collaborations/index_type' }
    end
  end

  ##
  # View Collaborator
  #
  # `GET /api/admin/container_registry/{container-registry-id}/collaborators/{id}`
  #
  # * `collaboration`: Object
  #     * `id`: String
  #     * `registry`: Object
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
  # `POST /api/admin/container_registry/{container-registry-id}/collaborators`
  #
  # * `collaborator`: Object
  #     * `user_email`: String
  #     * `skip_confirmation`: Boolean - Add and activate without email notification.
  #
  def create
    @collab = @registry.container_registry_collaborators.new user_email: collaborator_params[:user_email], current_user: current_user
    @collab.skip_confirmation = true if collaborator_params[:skip_confirmation]
    return api_obj_error(@collab.errors.full_messages) unless @collab.save
    render action: :show, status: :created
  end

  ##
  # Remove Collaborator
  #
  # `DELETE /api/admin/container_registry/{container-registry-id}/collaborators/{id}`
  #
  def destroy
    return api_obj_error(@collab.errors.full_messages) unless @collab.destroy
    render head: :accepted
  end

  private

  def find_collab
    @collab = @registry.container_registry_collaborators.find_by id: params[:id]
    return api_obj_missing if @collab.nil?
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:collaborator).permit(:user_email, :skip_confirmation)
  end

end
