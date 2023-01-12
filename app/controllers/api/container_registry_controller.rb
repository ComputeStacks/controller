##
# Container Registry API
class Api::ContainerRegistryController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :images_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :images_write }, only: %i[update create destroy], unless: :current_user

  before_action :load_registry, except: [:index, :create]

  ##
  # List all Container Registries
  #
  # `GET /api/container_registry`
  #
  # **OAuth Authorization Required**: `images_read`
  #
  # * `container_registries`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `status`: String
  #     * `endpoint`: String | url and port
  #     * `username`: String
  #     * `password`: String
  #     * `images`: Array
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @registries = paginate ContainerRegistry.find_all_for(current_user).order(:created_at)
  end

  ##
  # View Container Registry
  #
  # `GET /api/container_registry/{id}`
  #
  # **OAuth Authorization Required**: `images_read`
  #
  # * `container_registry`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `status`: String
  #     * `endpoint`: String | url and port
  #     * `username`: String
  #     * `password`: String
  #     * `images`: Array
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Update Container Registry
  #
  # `PATCH /api/container_registry/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `container_registry`: Object
  #     * `label`: String
  #
  def update
    respond_to do |format|
      if @registry.update(registry_params)
        format.json { render json: {}, status: :accepted }
        format.xml { render xml: {}, status: :accepted }
      else
        format.json { render json: {errors: registry.errors}, status: :bad_request }
        format.xml { render xml: {errors: registry.errors}, status: :bad_request }
      end
    end
  rescue => e
    return api_fatal_error(e, 'a55db85e89aecd4f')
  end


  ##
  # Create Container Registry
  #
  # `POST /api/container_registry`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `container_registry`: Object
  #     * `label`: String
  #
  def create
    @registry = current_user.container_registries.new(registry_params)
    @registry.current_user = current_user
    respond_to do |format|
      if @registry.valid? && @registry.save
        RegistryWorkers::ProvisionRegistryWorker.perform_async @registry.id
        format.any(:json, :xml) { render template: "api/container_registry/show", status: :created }
      else
        format.json { render json: {errors: @registry.errors}, status: :bad_request }
        format.xml { render xml: {errors: @registry.errors}, status: :bad_request }
      end
    end
  rescue => e
    return api_fatal_error(e, '916c7b337f1171d5')
  end

  ##
  # Delete Container Registry
  #
  # `DELETE /api/container_registry/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    respond_to do |format|
      if @registry.deployed_containers.empty?
        if @registry.destroy
          format.json { render json: {}, status: :accepted }
          format.xml { render xml: {}, status: :accepted }
        else
          format.json { render json: { errors: @registry.errors.full_messages }, status: :bad_request }
          format.xml { render xml: { errors: @registry.errors.full_messages }, status: :bad_request }
        end

      else
        format.json { render json: {errors: ["Error! There are deployed containers using this registry."]}, status: :bad_request }
        format.xml { render xml: {errors: ["Error! There are deployed containers using this registry."]}, status: :bad_request }
      end
    end
  rescue => e
    return api_fatal_error(e, 'e3851bbfe5d21988')
  end

  private

  def registry_params
    params.require(:container_registry).permit(:label)
  end

  def load_registry
    @registry = ContainerRegistry.find_for current_user, { id: params[:id] }
    return api_obj_missing if @registry.nil?
    @registry.current_user = current_user
  end

end
