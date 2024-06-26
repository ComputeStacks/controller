##
# Volumes API
class Api::VolumesController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update], unless: :current_user

  before_action :load_volume, only: :show
  before_action :load_volume_edit, only: :update

  ##
  # List all volumes
  #
  # `GET /api/volumes`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `volumes`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `region_id`: Integer
  #     * `to_trash`: Boolean
  #     * `trash_after`: DateTime
  #     * `size`: Decimal
  #     * `usage`: Decimal
  #     * `usage_checked`: DateTime
  #     * `trashed_by_id`: Integer
  #     * `detached_at`: DateTime
  #     * `subscription_id`: Integer
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
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #     * `volume_maps`: Array
  #         * `id`: Integer
  #         * `mount_ro`: Bool | Mount read only
  #         * `mount_path`: String
  #         * `container_service`: Object
  #             * `id`: Integer
  #             * `csrn`: String
  #             * `name`: String
  #             * `label`: String
  #     * `template`: Object
  #         * `id`: Integer
  #         * `csrn`: String
  #         * `container_image`: Object
  #             * `id`: Integer
  #             * `csrn`: String
  #             * `label`: String
  #
  def index
    @volumes = paginate Volume.find_all_for(current_user).active
  end

  ##
  # View Volume
  #
  # `GET /api/volumes/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `volume`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `region_id`: Integer
  #     * `to_trash`: Boolean
  #     * `trash_after`: DateTime
  #     * `size`: Decimal
  #     * `usage`: Decimal
  #     * `usage_checked`: DateTime
  #     * `trashed_by_id`: Integer
  #     * `detached_at`: DateTime
  #     * `subscription_id`: Integer
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
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #     * `volume_maps`: Array
  #         * `id`: Integer
  #         * `mount_ro`: Bool | Mount read only
  #         * `mount_path`: String
  #         * `container_service`: Object
  #             * `id`: Integer
  #             * `csrn`: String
  #             * `name`: String
  #             * `label`: String
  #     * `template`: Object
  #         * `id`: Integer
  #         * `csrn`: String
  #         * `container_image`: Object
  #             * `id`: Integer
  #             * `csrn`: String
  #             * `label`: String
  #
  def show; end

  ##
  # Update a volume
  #
  # `PATCH /api/volumes/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `volume`: Object
  #     * `borg_enabled`: Boolean
  #     * `borg_strategy`: String | custom file mariadb mysql postgres
  #     * `borg_freq`: String | cron schedule. Supports @daily, @weekly, @monthly.
  #     * `borg_keep_hourly`: Integer | Number of 'hourly' backups to keep.
  #     * `borg_keep_daily`: Integer | Number of 'daily' backups to keep.
  #     * `borg_keep_weekly`: Integer | Number of 'weekly' backups to keep.
  #     * `borg_keep_monthly`: Integer | Number of 'monthly' backups to keep.
  #     * `borg_keep_annually`: Integer | Number of 'annual' backups to keep.
  #
  def update
    if @volume.update(volume_params)
      render :show
    else
      api_obj_error @volume.errors.full_messages.to_sentence
    end
  end

  private

  # View permission
  def load_volume
    @volume = Volume.find_for current_user, id: params[:id]
    return api_obj_missing if @volume.nil?
  end

  # Edit permission
  def load_volume_edit
    @volume = Volume.find_for_edit current_user, id: params[:id]
    return api_obj_missing if @volume.nil?
  end

  def volume_params
    params.require(:volume).permit(
      :borg_freq, :borg_strategy, :borg_keep_hourly, :borg_keep_daily, :borg_keep_weekly,
      :borg_keep_monthly, :borg_rollback, :borg_enabled, :borg_keep_annually
    )
  end

end
