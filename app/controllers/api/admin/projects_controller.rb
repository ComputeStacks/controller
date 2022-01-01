##
# # Projects
class Api::Admin::ProjectsController < Api::Admin::ApplicationController

  before_action :find_project, except: %i[ index ]

  ##
  # List All Projects
  #
  # `GET /api/admin/users/{user_id}/projects`
  # `GET /api/admin/projects`
  #
  # * `projects`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `current_state`: String
  #     * `container_image_ids`: Array<Integer>
  #     * `user`: Object
  #         * `id`: Integer
  #         * `full_name`: String
  #         * `email`: String
  #         * `external_id`: String
  #         * `labels`: Object
  #     * `links`: Object
  #         * `services`: String
  #         * `container_images`: String
  #         * `bastions`: String
  #     * `metadata`: Object
  #         * `icons`: Array
  #         * `image_names`: Array
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    if params[:user_id] && !params[:user_id].to_i.zero?
      user = User.find_by(id: params[:user_id])
      return api_obj_missing(["Unknown user."]) if user.nil?
      @deployments = paginate user.deployments.sorted
    else
      @deployments = paginate Deployment.all.sorted
    end
    respond_to :json, :xml
  end

  ##
  # View Project
  #
  # `GET /api/admin/projects/{id}`
  #
  # * `project`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `current_state`: String
  #     * `container_image_ids`: Array<Integer>
  #     * `user`: Object
  #         * `id`: Integer
  #         * `full_name`: String
  #         * `email`: String
  #         * `external_id`: String
  #         * `labels`: Object
  #     * `links`: Object
  #         * `services`: String
  #         * `container_images`: String
  #         * `bastions`: String
  #     * `metadata`: Object
  #         * `icons`: Array
  #         * `image_names`: Array
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def show
    respond_to :json, :xml
  end

  ##
  # Update Project
  #
  # `PATCH /api/admin/projects/{id}`
  #
  # Changing project ownership:
  # To change the owner of a project, you simply need to pass the new `user_id` in your patch request.
  # If the project uses custom images, then the update will fail because the new owner does not have ownership
  # of the images it uses. You have two options:
  #   1. Add the user as a collaborator on that custom image, or;
  #   2. Change the owner of the custom image.
  #
  # Params:
  # * `project`: Object
  #   * `name`: String - project name
  #   * `user_id`: Integer - Only supply this if you want to change the project owner!
  #   * `migrate_image_owner`: Boolean - (default: false)

  def update
    audit = Audit.create_from_object!(@deployment, 'updated', request.remote_ip, current_user)
    @deployment.current_audit = audit
    return api_obj_error(@deployment.errors.full_messages) unless @deployment.update(project_params)
    respond_to do |f|
      f.any(:json, :xml) { render action: :show }
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :user_id)
  end

  def find_project
    @deployment = Deployment.find_by id: params[:id]
    return api_obj_missing if @deployment.nil?
  end

end
