##
# Container Registry Collaborators
class Api::ContainerRegistry::CollaboratorsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :images_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :images_write }, only: %i[update create destroy], unless: :current_user

  before_action :load_registry
  before_action :find_collab, only: %i[show destroy]

  ##
  # List All Collaborators
  #
  # `GET /api/container_registry/{container-registry-id}/collaborators`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
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
  # `GET /api/container_registry/{container-registry-id}/collaborators/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
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
  # `POST /api/container_registry/{container-registry-id}/collaborators`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `collaborator`: Object
  #     * `user_email`: String
  #
  def create
    @collab = @registry.container_registry_collaborators.new user_email: collaborator_params[:user_email], current_user: current_user
    return api_obj_error(@collab.errors.full_messages) unless @collab.save
    render action: :show, status: :created
  end

  ##
  # Remove Collaborator
  #
  # `DELETE /api/container_registry/{container-registry-id}/collaborators/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  def destroy
    return api_obj_error(@collab.errors.full_messages) unless @collab.destroy
    render head: :accepted
  end

  private

  def load_registry
    @registry = ContainerRegistry.find_for current_user, { id: params[:container_registry_id] }
    return api_obj_missing if @registry.nil?
    return api_obj_missing unless @registry.can_administer?(current_user)
    @registry.current_user = current_user
  end

  def find_collab
    @collab = @registry.container_registry_collaborators.find_by id: params[:id]
    return api_obj_missing if @collab.nil?
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:collaborator).permit(:user_email)
  end

end
