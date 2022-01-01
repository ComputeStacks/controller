##
# Container Services API
class Api::ContainerServicesController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update create destroy], unless: :current_user

  before_action :load_service, except: %i[ index create ]

  ##
  # List all container services
  #
  # `GET /api/container_services`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `container_services`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `default_domain`: String
  #     * `public_ip`: String
  #     * `command`: String
  #     * `is_load_balancer`: Boolean
  #     * `has_domain_management`: Boolean
  #     * `container_image_id`: Integer
  #     * `current_state`: String
  #     * `auto_scale`: Boolean
  #     * `auto_scale_horizontal`: Boolean
  #     * `auto_scale_max`: Boolean
  #     * `labels`: Object
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `project`: Object
  #         * `id`: Integer
  #         * `name`: String
  #     * `package`: Object
  #         * `label`: String
  #         * `cpu`: Decimal
  #         * `memory`: Integer
  #         * `storage`: Integer
  #         * `bandwidth`: Integer
  #         * `local_disk`: Integer
  #         * `backup`: Integer
  #         * `memory_swap`: Integer
  #         * `memory_swappiness`: Integer
  #     * `has_sftp`: Boolean
  #     * `ingress_rules`: Array<Integer>
  #     * `product_id`: Integer
  #     * `bastions`: Array<Integer>
  #     * `domains`: Array<Integer>
  #     * `deployed_containers`: Integer
  #     * `help`: Object
  #         * `general`: String
  #         * `ssh`: String
  #         * `remote`: String
  #         * `domain`: String
  #     * `links`: Object
  #         * `project`: String (url)
  #         * `bastions`: String (url)
  #         * `containers`: String (url)
  #         * `events`: String (url)
  #         * `ingress_rules`: String (url)
  #         * `metadata`: String (url)
  #         * `logs`: String (url)
  #         * `products`: String (url)
  #
  def index
    @services = paginate Deployment::ContainerService.find_all_for(current_user)
  end

  ##
  # View Container Service
  #
  # `GET /api/container_services/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `container_service`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `default_domain`: String
  #     * `public_ip`: String
  #     * `command`: String
  #     * `is_load_balancer`: Boolean
  #     * `has_domain_management`: Boolean
  #     * `container_image_id`: Integer
  #     * `current_state`: String
  #     * `auto_scale`: Boolean
  #     * `auto_scale_horizontal`: Boolean
  #     * `auto_scale_max`: Boolean
  #     * `labels`: Object
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `project`: Object
  #         * `id`: Integer
  #         * `name`: String
  #     * `package`: Object
  #         * `label`: String
  #         * `cpu`: Decimal
  #         * `memory`: Integer
  #         * `storage`: Integer
  #         * `bandwidth`: Integer
  #         * `local_disk`: Integer
  #         * `backup`: Integer
  #         * `memory_swap`: Integer
  #         * `memory_swappiness`: Integer
  #     * `has_sftp`: Boolean
  #     * `ingress_rules`: Array<Integer>
  #     * `product_id`: Integer
  #     * `bastions`: Array<Integer>
  #     * `domains`: Array<Integer>
  #     * `deployed_containers`: Integer
  #     * `help`: Object
  #         * `general`: String
  #         * `ssh`: String
  #         * `remote`: String
  #         * `domain`: String
  #     * `links`: Object
  #         * `project`: String (url)
  #         * `bastions`: String (url)
  #         * `containers`: String (url)
  #         * `events`: String (url)
  #         * `ingress_rules`: String (url)
  #         * `metadata`: String (url)
  #         * `logs`: String (url)
  #         * `products`: String (url)
  #
  def show; end

  ##
  # Update a container service
  #
  # `PATCH /api/container_services/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `container_service`: Object
  #     * `name`: String
  #     * `scale`: Integer
  #     * `package_id`: Integer
  #
  def update
    if @service.update(current_user.is_admin ? admin_service_params : container_service_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @service.errors.full_messages
    end
  end

  ##
  # Delete a container service
  #
  # `DELETE /api/container_services/{id}`
  #
  #  **OAuth AuthorizationRequired**: `projects_write`
  #
  def destroy
    audit = Audit.create_from_object!(@service, 'deleted', request.remote_ip, current_user)
    event = EventLog.create!(
      locale: 'service.trash',
      locale_keys: { label: @service.name },
      event_code: '859369ca114615bb',
      audit: audit,
      status: 'pending'
    )
    event.container_services << @service
    ContainerServiceWorkers::TrashServiceWorker.perform_async @service.to_global_id.uri, event.to_global_id.uri
    respond_to do |format|
      format.json { render json: {}, status: :accepted }
      format.xml { render xml: {}, status: :accepted }
    end

  end

  private

  def container_service_params # :doc:
    if current_api_version < 51
      params.permit(:name, :scale, :package_id, {resources: [:cpu, :memory]})
    else
      params.require(:container_service).permit(:label, :command, :tag_list)
    end
  end

  def admin_service_params
    params.require(:container_service).permit(:label, :command, :tag_list, :override_autoremove)
  end

  def load_service  # :doc:
    @service = Deployment::ContainerService.find_for current_user, id: params[:id]
    return api_obj_missing if @service.nil?
    @service.current_user = current_user
  end

end
