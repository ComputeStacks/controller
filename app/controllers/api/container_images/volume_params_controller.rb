##
# Container Images
class Api::ContainerImages::VolumeParamsController < Api::ContainerImages::BaseController

  before_action :find_volume, only: %i[show update destroy]

  ##
  # List all volumes
  #
  # `GET /api/container_images/{container-image-id}/volume_params`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `volume_params`: Array
  #     * `id`: Integer
  #     * `label`: String
  #     * `mount_path`: String
  #     * `enable_sftp`: Boolean
  #     * `borg_enabled`: Boolean
  #     * `borg_freq`: String
  #     * `borg_strategy`: `String<file,mysql>`
  #     * `borg_keep_hourly`: Integer
  #     * `borg_keep_daily`: Integer
  #     * `borg_keep_weekly`: Integer
  #     * `borg_keep_monthly`: Integer
  #     * `borg_keep_annually`: Integer
  #     * `borg_pre_backup`: `Array<String>`
  #     * `borg_post_backup`: `Array<String>`
  #     * `borg_pre_restore`: `Array<String>`
  #     * `borg_post_restore`: `Array<String>`
  #     * `borg_rollback`: `Array<String>`
  #     * `mount_ro`: Bool
  #     * `source_volume_id`: Integer | VolumeParam, not Volume.
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #
  def index
    @volumes = @image.volumes
  end

  ##
  # View a single volume
  #
  # `GET /api/container_images/{container-image-id}/volume_params/{id}`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `volume_params`: Object
  #     * `id`: Integer
  #     * `label`: String
  #     * `mount_path`: String
  #     * `enable_sftp`: Boolean
  #     * `borg_enabled`: Boolean
  #     * `borg_freq`: String
  #     * `borg_strategy`: `String<file,mysql>`
  #     * `borg_keep_hourly`: Integer
  #     * `borg_keep_daily`: Integer
  #     * `borg_keep_weekly`: Integer
  #     * `borg_keep_monthly`: Integer
  #     * `borg_keep_annually`: Integer
  #     * `borg_pre_backup`: `Array<String>`
  #     * `borg_post_backup`: `Array<String>`
  #     * `borg_pre_restore`: `Array<String>`
  #     * `borg_post_restore`: `Array<String>`
  #     * `borg_rollback`: `Array<String>`
  #     * `mount_ro`: Bool
  #     * `source_volume_id`: Integer | VolumeParam, not Volume.
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #
  def show; end

  ##
  # Update a volume
  #
  # `PATCH /api/container_images/{container-image-id}/volume_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `volume_params`: Object
  #     * `label`: String
  #     * `mount_path`: String
  #     * `enable_sftp`: Boolean
  #     * `borg_enabled`: Boolean
  #     * `borg_freq`: String
  #     * `borg_strategy`: `String<file,mysql>`
  #     * `borg_keep_hourly`: Integer
  #     * `borg_keep_daily`: Integer
  #     * `borg_keep_weekly`: Integer
  #     * `borg_keep_monthly`: Integer
  #     * `borg_keep_annually`: Integer
  #     * `borg_pre_backup`: `Array<String>`
  #     * `borg_post_backup`: `Array<String>`
  #     * `borg_pre_restore`: `Array<String>`
  #     * `borg_post_restore`: `Array<String>`
  #     * `borg_rollback`: `Array<String>`
  #     * `mount_ro`: Bool
  #     * `source_volume_id`: Integer | VolumeParam, not Volume.
  #
  def update
    if @volume.update(volume_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @volume.errors.full_messages
    end
  end

  ##
  # Create a volume
  #
  # `POST /api/container_images/{container-image-id}/volume_params`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `volume_params`: Object
  #     * `label`: String
  #     * `mount_path`: String
  #     * `enable_sftp`: Boolean
  #     * `borg_enabled`: Boolean
  #     * `borg_freq`: String
  #     * `borg_strategy`: `String<file,mysql>`
  #     * `borg_keep_hourly`: Integer
  #     * `borg_keep_daily`: Integer
  #     * `borg_keep_weekly`: Integer
  #     * `borg_keep_monthly`: Integer
  #     * `borg_keep_annually`: Integer
  #     * `borg_pre_backup`: `Array<String>`
  #     * `borg_post_backup`: `Array<String>`
  #     * `borg_pre_restore`: `Array<String>`
  #     * `borg_post_restore`: `Array<String>`
  #     * `borg_rollback`: `Array<String>`
  #     * `mount_ro`: Bool
  #     * `source_volume_id`: Integer | VolumeParam, not Volume.
  #
  def create
    @volume = @image.volumes.new(volume_params)
    @volume.current_user = current_user
    @volume.borg_freq = '@daily' if volume_params[:borg_freq].blank?
    @volume.borg_keep_daily = '5' if volume_params[:borg_keep_daily].blank?
    @volume.borg_keep_weekly = '2' if volume_params[:borg_keep_weekly].blank?
    @volume.borg_keep_monthly = '3' if volume_params[:borg_keep_monthly].blank?
    if @volume.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @volume.errors.full_messages
    end
  end

  ##
  # Delete a volume
  #
  # `DELETE /api/container_images/{container-image-id}/volume_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    @volume.destroy ? api_obj_destroyed : api_obj_error(@volume.errors.full_messages)
  end


  private

  def volume_params
    params.require(:volume_param).permit(
                                                   :mount_path, :enable_sftp, :label, :borg_enabled, :borg_freq, :borg_strategy,
                                                   :source_volume_id, :mount_ro, :borg_keep_annually,
                                                   :borg_keep_hourly, :borg_keep_weekly, :borg_keep_monthly, :borg_backup_error,
                                                   :borg_restore_error, borg_pre_backup: [], borg_post_backup: [], borg_pre_restore: [],
                                                   borg_post_restore: [], borg_rollback: []
    )
  end

  def find_volume
    @volume = @image.volumes.find_by(id: params[:id])
    return api_obj_missing if @volume.nil?
    @volume.current_user = current_user
  end

end
