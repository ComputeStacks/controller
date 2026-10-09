##
# Projects API
class Api::ProjectsController < Api::ApplicationController
  api_scope read: :project_read, update: :project_write, destroy: :project_write

  before_action :load_deployment, except: %i[index create]

  ##
  # List Projects
  #
  # `GET /api/projects`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `projects`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `skip_ssh`: Boolean
  #     * `current_state`: String<working,alert,ok,deleting>
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `container_image_ids`: Array<Integer>
  #     * `node_status`: Object - availability of the nodes running the project's containers and bastions
  #       (nothing deployed yet: its availability zones' nodes). Read from stored state.
  #         * `state`: String<online,maintenance,offline> - worst state among those nodes
  #         * `since`: DateTime | null - when that state began
  #         * `planned`: Boolean - true for maintenance, false for an unplanned outage
  #         * `message`: String | null - operator's notice to customers; null while `online`
  #         * `operations`: Object - what each action does in this state (see doc/maintenance.md)
  #             * `power`: String<available,deferred,refused> - deferred runs when maintenance ends; latest request wins
  #             * `backup`, `restore`, `export`, `scale`, `bastion_password_reset`: String<available,refused>
  #             * `config_changes`: String<available,deferred> - deferred until the node reconnects
  #     * `links`: Hash
  #         * `services`: String (url)
  #         * `container_images`: String (url)
  #         * `bastions`: String (url)
  #     * `metadata`: Hash
  #         * `icons`: Array
  #         * `image_names`: Array

  def index
    @deployments = paginate Deployment.find_all_for(current_user).sort_by_name
      .preload(services: [{containers: :node}, {region: :nodes}], sftp_containers: :node)
    @images = ContainerImage.find_all_for(current_user, true)
  end

  ##
  # View Project
  #
  # `GET /api/projects/{id}`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `project`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `skip_ssh`: Boolean
  #     * `current_state`: String<working,alert,ok,deleting>
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `container_image_ids`: Array<Integer>
  #     * `node_status`: Object - availability of the nodes running the project's containers and bastions
  #       (nothing deployed yet: its availability zones' nodes). Read from stored state.
  #         * `state`: String<online,maintenance,offline> - worst state among those nodes
  #         * `since`: DateTime | null - when that state began
  #         * `planned`: Boolean - true for maintenance, false for an unplanned outage
  #         * `message`: String | null - operator's notice to customers; null while `online`
  #         * `operations`: Object - what each action does in this state (see doc/maintenance.md)
  #             * `power`: String<available,deferred,refused> - deferred runs when maintenance ends; latest request wins
  #             * `backup`, `restore`, `export`, `scale`, `bastion_password_reset`: String<available,refused>
  #             * `config_changes`: String<available,deferred> - deferred until the node reconnects
  #     * `links`: Hash
  #         * `services`: String (url)
  #         * `container_images`: String (url)
  #         * `bastions`: String (url)
  #     * `metadata`: Hash
  #         * `icons`: Array
  #         * `image_names`: Array

  def show
  end

  ##
  # Update Project
  #
  # `PATCH /api/projects/{id}`
  #
  # **OAuth AuthorizationRequired**: `project_write`
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
  # **OAuth AuthorizationRequired**: `project_write`
  #
  def destroy
    audit = Audit.create_from_object!(@deployment, "deleted", request.remote_ip, current_user)
    event = EventLog.create!(
      locale: "deployment.trash",
      locale_keys: {project: @deployment.name},
      event_code: "20cd984da4da8963",
      audit: audit,
      status: "pending"
    )
    @deployment.mark_trashed!
    event.deployments << @deployment
    ProjectWorkers::TrashProjectWorker.perform_async @deployment.global_id, event.global_id
    api_obj_destroyed
  rescue => e
    api_fatal_error(e, "337f9ab41ca0a9a7")
  end

  private

  def project_params
    params.require(:project).permit(:name)
  end

  def load_deployment
    @deployment = Deployment.find_for current_user, id: params[:id]
    api_obj_missing if @deployment.nil?
  end
end
