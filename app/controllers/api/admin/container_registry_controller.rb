##
# Container Registry
class Api::Admin::ContainerRegistryController < Api::Admin::ApplicationController

  before_action :load_registry, except: [:index, :create]

  # List all Registries
  #
  # `GET /api/admin/container_registry`
  #
  # * `container_registries`: Array
  #   * `id`: Integer
  #   * `name`: String
  #   * `label`: String
  #   * `status`: String [new,deploying,deployed,error,working]
  #   * `endpoint`: String
  #   * `username`: String
  #   * `password`: String
  #   * `images`: Array of Strings
  #   * `created_at`: DateTime
  #   * `updated_at`: DateTime

  def index
    @registries = paginate ContainerRegistry.all.order(:created_at)
  end

  # View Container Registry
  #
  # `GET /api/admin/container_registry/{id}`
  #
  # * `container_registry`: Object
  #   * `id`: Integer
  #   * `name`: String
  #   * `label`: String
  #   * `status`: String [new,deploying,deployed,error,working]
  #   * `endpoint`: String
  #   * `username`: String
  #   * `password`: String
  #   * `images`: Array of Strings
  #   * `created_at`: DateTime
  #   * `updated_at`: DateTime

  def show; end

  # Update Container Registry
  #
  # `PATCH /api/admin/container_registry/{id}`
  #
  # * `container_registry`: Object
  #   * `label`: String
  #   * `user_id`: Integer - Only supply if you wish to change owner.

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
    return api_fatal_error(e, '491d8878e76f6f8c')
  end

  # Create Container Registry
  #
  # `POST /api/admin/container_registry`
  #
  # * `container_registry`: Object
  #   * `label`: String
  #   * `user_id`: Integer

  def create
    @registry = ContainerRegistry.new(registry_params)
    @registry.current_user = current_user
    respond_to do |format|
      if @registry.valid? && @registry.save
        RegistryWorkers::ProvisionRegistryWorker.perform_async @registry.id
        format.any(:json, :xml) { render template: "api/admin/container_registry/show", status: :created }
      else
        format.json { render json: {errors: @registry.errors}, status: :bad_request }
        format.xml { render xml: {errors: @registry.errors}, status: :bad_request }
      end
    end
  rescue => e
    return api_fatal_error(e, 'ac39278afd586653')
  end

  # Delete Container Registry
  #
  # `DESTROY /api/admin/container_registry/{id}`
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
    return api_fatal_error(e, 'b32af383f7088db8')
  end

  private

  def registry_params
    params.require(:container_registry).permit(:label, :user_id)
  end

  def load_registry
    @registry = ContainerRegistry.find params[:id]
    @registry.current_user = current_user
  end

end
