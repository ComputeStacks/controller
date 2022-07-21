##
# Container Image Environmental Variable
class Api::ContainerImages::EnvParamsController < Api::ContainerImages::BaseController

  before_action :find_env, only: [:show, :update, :destroy]

  ##
  # List all environmental parameters
  #
  # `GET /api/container_images/{container-image-id}/env_params`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `env_params`: Array
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: String<static,variable>
  #     * `env_value`: String | when param_type == variable
  #     * `static_value`: String | when param_type == static
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @envs = @image.env_params.sorted
  end

  ##
  # View environmental parameter
  #
  # `GET /api/container_images/{container-image-id}/env_params/{id}`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `env_param`: Object
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: String<static,variable>
  #     * `env_value`: String | when param_type == variable
  #     * `static_value`: String | when param_type == static
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Update an environmental parameter
  #
  # `PATCH /api/container_images/{container-image-id}/env_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `env_param`: Object
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: String<static,variable>
  #     * `env_value`: String
  #     * `static_value`: String
  #
  def update
    if @env.update(env_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @env.errors.full_messages
    end
  end

  ##
  # Create an environmental parameter
  #
  # `POST /api/container_images/{container-image-id}/env_params`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `env_param`: Object
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: String<static,variable>
  #     * `env_value`: String
  #     * `static_value`: String
  #
  def create
    @env = @image.env_params.new(env_params)
    @env.current_user = current_user
    if @env.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @env.errors.full_messages
    end
  end

  ##
  # Delete Env Param
  #
  # `DELETE /api/container_images/{container-image-id}/env_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    @env.destroy ? api_obj_destroyed : api_obj_error(@env.errors.full_messages)
  end

  private

  def find_env
    @env = @image.env_params.find_by(id: params[:id])
    return api_obj_missing if @env.nil?
    @env.current_user = current_user
    @env.static_value = @env.value if @env.param_type == 'static'
    @env.env_value = @env.value if @env.param_type == 'variable'
  end

  def env_params
    params.require(:env_param).permit(
      :name, :label, :param_type, :static_value, :env_value
    )
  end


end
