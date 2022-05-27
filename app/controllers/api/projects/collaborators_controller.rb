# Project Collaborators
class Api::Projects::CollaboratorsController < Api::Projects::BaseController

  before_action :verify_admin
  before_action :find_collab, only: %i[show destroy]

  ##
  # List All Collaborators
  #
  # `GET /api/projects/{project-id}/collaborators`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  #   * `collaborations`: Array
  #       * `id`: Integer
  #       * `collaborator`: Object
  #           * `id`: Integer
  #           * `email`: String
  #           * `full_name`: String
  #
  def index
    @collaborators = @deployment.deployment_collaborators.sorted
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/collaborations/index_type' }
    end
  end

  ##
  # View Collaborator
  #
  # `GET /api/projects/{project-id}/collaborators/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `collaboration`: Object
  #     * `id`: String
  #     * `project`: Object
  #         * `id`: Integer
  #         * `name`: String
  # * `collaborator`: Object
  #     * `id`: Integer
  #     * `email`: String
  #     * `full_name`: String
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
  # `POST /api/projects/{project-id}/collaborators`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `collaborator`: Object
  #     * `user_email`: String
  #
  def create
    @collab = @deployment.deployment_collaborators.new user_email: collaborator_params[:user_email], current_user: current_user
    return api_obj_error(@collab.errors.full_messages) unless @collab.save
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/collaborations/show', status: :created }
    end
  end

  ##
  # Remove Collaborator
  #
  # `DELETE /api/projects/{project-id}/collaborators/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  def destroy
    return api_obj_error(@collab.errors.full_messages) unless @collab.destroy
    head :accepted
  end

  private

  # Only allow resource owner and admin to manage collaborators
  def verify_admin
    unless @deployment.can_administer? current_user
      head :unauthorized
    end
  end

  def find_collab
    @collab = @deployment.deployment_collaborators.find params[:id]
    return api_obj_missing if @collab.nil?
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:collaborator).permit(:user_email)
  end

end
