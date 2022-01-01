##
# Projects API
class Api::ProjectsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update destroy], unless: :current_user

  before_action :load_deployment, except: %i[ index create ]

  ##
  # List Projects
  #
  # `GET /api/projects`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `projects`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `skip_ssh`: Boolean
  #     * `current_state`: String<working,alert,ok,deleting>
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `container_image_ids`: Array<Integer>
  #     * `links`: Hash
  #         * `services`: String (url)
  #         * `container_images`: String (url)
  #         * `bastions`: String (url)
  #     * `metadata`: Hash
  #         * `icons`: Array
  #         * `image_names`: Array

  def index
    @deployments = paginate Deployment.find_all_for(current_user).sort_by_name
    @images = ContainerImage.find_all_for(current_user, true)
  end

  ##
  # View Project
  #
  # `GET /api/projects/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `project`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `skip_ssh`: Boolean
  #     * `current_state`: String<working,alert,ok,deleting>
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `container_image_ids`: Array<Integer>
  #     * `links`: Hash
  #         * `services`: String (url)
  #         * `container_images`: String (url)
  #         * `bastions`: String (url)
  #     * `metadata`: Hash
  #         * `icons`: Array
  #         * `image_names`: Array

  def show; end

  ##
  # Update Project
  #
  # `PATCH /api/projects/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `project`: Object
  #     * `name`: String

  def update
    return api_obj_error(@deployment.errors.full_messages) unless @deployment.update(project_params)
    render action: :show
  end

  ##
  # Delete Project
  #
  # `DELETE /api/projects/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  def destroy
    audit = Audit.create_from_object!(@deployment, 'deleted', request.remote_ip, current_user)
    event = EventLog.create!(
      locale: 'deployment.trash',
      locale_keys: { project: @deployment.name },
      event_code: '20cd984da4da8963',
      audit: audit,
      status: 'pending'
    )
    @deployment.mark_trashed!
    event.deployments << @deployment
    ProjectWorkers::TrashProjectWorker.perform_async @deployment.to_global_id.uri, event.to_global_id.uri
    api_obj_destroyed
  rescue => e
    return api_fatal_error(e, '337f9ab41ca0a9a7')
  end

  private

  def project_params
    params.require(:project).permit(:name)
  end

  def load_deployment
    @deployment = Deployment.find_for current_user, id: params[:id]
    return api_obj_missing if @deployment.nil?
  end

end
