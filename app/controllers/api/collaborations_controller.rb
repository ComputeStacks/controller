# User Collaborations
class Api::CollaborationsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :profile_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :profile_update }, only: %i[update destroy], unless: :current_user

  before_action :find_collab, except: :index

  ##
  # List All Collaborations
  #
  # `GET /api/collaborations`
  #
  #   * `projects`: Array
  #       * `id`: String
  #       * `owner`: Object
  #           * `id`: Integer
  #           * `email`: String
  #           * `full_name`: String
  #       * `project`: Object
  #           * `id`: Integer
  #           * `name`: String
  #   * `domains`: Array
  #       * `id`: String
  #       * `owner`: Object
  #           * `id`: Integer
  #           * `email`: String
  #           * `full_name`: String
  #       * `domain`: Object
  #           * `id`: Integer
  #           * `name`: String
  #   * `images`: Array
  #       * `id`: String
  #       * `owner`: Object
  #           * `id`: Integer
  #           * `email`: String
  #           * `full_name`: String
  #       * `image`: Object
  #           * `id`: Integer
  #           * `name`: String
  #   * `registries`: Array
  #       * `id`: String
  #       * `owner`: Object
  #           * `id`: Integer
  #           * `email`: String
  #           * `full_name`: String
  #       * `registry`: Object
  #           * `id`: Integer
  #           * `name`: String
  #
  def index
    @projects = DeploymentCollaborator.find_all_for_user current_user
    @registries = ContainerRegistryCollaborator.find_all_for_user current_user
    @domains = Dns::ZoneCollaborator.find_all_for_user current_user
    @images = ContainerImageCollaborator.find_all_for_user current_user
  end

  ##
  # View Collaboration
  #
  # `GET /api/collaborations/{id}`
  #
  # * `collaboration`: Object
  #     * `id`: String
  #     * `{resource}`: Object - Where `resource` is one of: project, image, zone, registry
  #         * `id`: Integer
  #         * `name`: String
  # * `resource_owner`: Object
  #     * `id`: Integer
  #     * `email`: String
  #     * `full_name`: String
  #
  def show; end

  ##
  # Activate Collaboration
  #
  # When initially invited, the active will be disabled.
  #
  # `PATCH /api/collaborations/{id}`
  #
  # * `Collaboration`: Object
  #     * `active`: Boolean
  #
  def update
    if @collab.update collab_params
      render action: :show, status: :accepted
    else
      api_obj_error @collab.errors.full_messages
    end
  end

  ##
  # Delete Collaboration
  #
  # `DELETE /api/collaboration/{id}`
  #
  def destroy
    if @collab.destroy
      head :accepted
    else
      api_obj_error @collab.errors.full_messages
    end
  end

  private

  def find_collab
    # params[:id] = ID-model
    id = params[:id].split('-')[0].to_i
    collab_model = params[:id].split('-')[1]
    allowed_models = %w(project image registry zone)
    @collab = if allowed_models.include?(collab_model) && id > 0
                case collab_model
                when 'project'
                  DeploymentCollaborator.find_for_user current_user, id: id
                when 'image'
                  ContainerImageCollaborator.find_for_user current_user, id: id
                when 'registry'
                  ContainerRegistryCollaborator.find_for_user current_user, id: id
                when 'zone'
                  Dns::ZoneCollaborator.find_for_user current_user, id: id
                else
                  nil
                end
              else
                nil
              end
    api_obj_missing if @collab.nil?
  end

  def collab_params
    params.require(:collaboration).permit(:active)
  end

end
