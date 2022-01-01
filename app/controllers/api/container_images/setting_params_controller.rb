##
# Setting Parameters
class Api::ContainerImages::SettingParamsController < Api::ContainerImages::BaseController

  before_action :find_setting, only: [:show, :update, :destroy]

  ##
  # List all image settings
  #
  # `GET /api/container_images/{container-image-id}/setting_params`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `setting_params`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: `String<password,static>`
  #     * `value`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @settings = @image.setting_params.sorted
  end

  ##
  # View a single setting
  #
  # `GET /api/container_images/{container-image-id}/setting_params/{id}`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `setting_param`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: `String<password,static>`
  #     * `value`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Update a setting
  #
  # `PATCH /api/container_images/{container-image-id}/setting_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `setting_param`: Object
  #     * `label`: String
  #     * `name`: String
  #     * `param_type`: String<password,static>
  #     * `value`: String
  #
  def update
    if @setting.update(setting_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @setting.errors.full_messages
    end
  end

  ##
  # Create a setting
  #
  # `POST /api/container_images/{container-image-id}/setting_params`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `setting_param`: Object
  #     * `label`: String
  #     * `name`: String
  #     * `param_type`: String<password,static>
  #     * `value`: String
  #
  def create
    @setting = @image.setting_params.new(setting_params)
    @setting.current_user = current_user
    if @setting.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @setting.errors.full_messages
    end
  end

  ##
  # Delete a setting
  #
  # `DELETE /api/container_images/{container-image-id}/setting_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    @setting.destroy ? api_obj_destroyed : api_obj_error(@setting.errors.full_messages)
  end


  private

  def find_setting
    @setting = @image.setting_params.find_by(id: params[:id])
    return api_obj_missing if @setting.nil?
    @setting.current_user = current_user
  end

  def setting_params
    params.require(:setting_param).permit(:name, :label, :param_type, :value)
  end


end
