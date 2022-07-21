##
# # Volumes
class Api::Admin::VolumesController < Api::Admin::ApplicationController

  before_action :load_user

  ##
  # List All Volumes
  #
  # You may optionally include `?user_id=` to filter volumes by user.
  #
  # Returns:
  # * `volumes`: Array
  #   * `id`: Integer
  #   * `name`: String
  #   * `label`: String
  #   * `user`: Object
  #       * `id`: Integer
  #       * `email`: String
  #       * `external_id`: String
  #       * `labels`: Object
  #   * `region_id`: Integer
  #   * `to_trash`: Boolean
  #   * `trash_after`: DateTime
  #   * `usage`: Integer - In GB
  #   * `usage_checked`: DateTime
  #   * `trashed_by_id`: Integer - User who initiated the deletion process
  #   * `detached_at`: DateTime - when the volume was detached from the service
  #   * `subscription_id`: Integer
  #   * `enable_sftp`: Boolean
  #   * `borg_enabled`: Boolean - Are backups enabled?
  #   * `borg_freq`: String - Cron syntax
  #   * `borg_strategy`: String - file or mysql
  #   * `borg_keep_hourly`: Integer
  #   * `borg_keep_daily`: Integer
  #   * `borg_keep_weekly`: Integer
  #   * `borg_keep_monthly`: Integer
  #   * `borg_keep_annually`: Integer
  #   * `borg_pre_backup`: Array<String> - scripts inside of the container to run before backup
  #   * `borg_pre_restore`: Array<String>
  #   * `borg_post_restore`: Array<String>
  #   * `borg_rollback`: Array<String>
  #   * `volume_backend`: String - either nfs or local
  #   * `created_at`: DateTime
  #   * `updated_at`: DateTime
  #   * `volume_maps`: Array
  #       * `id`: Integer
  #       * `mount_ro`: Bool | Mount read only
  #       * `mount_path`: String
  #       * `container_service`: Object
  #           * `id`: Integer
  #           * `csrn`: String
  #           * `name`: String
  #           * `label`: String
  #   * `template`: Object
  #       * `id`: Integer
  #       * `csrn`: String
  #       * `container_image`: Object
  #           * `id`: Integer
  #           * `csrn`: String
  #           * `label`: String
  #
  def index
    @volumes = paginate(@user ? @user.volumes.active.sorted : Volume.active.sorted)
  end

  ##
  # View Volume
  #
  # Returns:
  # * `volume`: Object
  #   * `id`: Integer
  #   * `name`: String
  #   * `label`: String
  #   * `user`: Object
  #       * `id`: Integer
  #       * `email`: String
  #       * `external_id`: String
  #       * `labels`: Object
  #   * `region_id`: Integer
  #   * `to_trash`: Boolean
  #   * `trash_after`: DateTime
  #   * `usage`: Integer - In GB
  #   * `usage_checked`: DateTime
  #   * `trashed_by_id`: Integer - User who initiated the deletion process
  #   * `detached_at`: DateTime - when the volume was detached from the service
  #   * `subscription_id`: Integer
  #   * `enable_sftp`: Boolean
  #   * `borg_enabled`: Boolean - Are backups enabled?
  #   * `borg_freq`: String - Cron syntax
  #   * `borg_strategy`: String - file or mysql
  #   * `borg_keep_hourly`: Integer
  #   * `borg_keep_daily`: Integer
  #   * `borg_keep_weekly`: Integer
  #   * `borg_keep_monthly`: Integer
  #   * `borg_keep_annually`: Integer
  #   * `borg_pre_backup`: Array<String> - scripts inside of the container to run before backup
  #   * `borg_pre_restore`: Array<String>
  #   * `borg_post_restore`: Array<String>
  #   * `borg_rollback`: Array<String>
  #   * `volume_backend`: String - either nfs or local
  #   * `created_at`: DateTime
  #   * `updated_at`: DateTime
  #   * `volume_maps`: Array
  #       * `id`: Integer
  #       * `mount_ro`: Bool | Mount read only
  #       * `mount_path`: String
  #       * `container_service`: Object
  #           * `id`: Integer
  #           * `csrn`: String
  #           * `name`: String
  #           * `label`: String
  #   * `template`: Object
  #       * `id`: Integer
  #       * `csrn`: String
  #       * `container_image`: Object
  #           * `id`: Integer
  #           * `csrn`: String
  #           * `label`: String
  #
  def show
    @volume = Volume.find params[:id]
  end

  private

  def load_user
    if params[:user_id]
      @user = User.find_by(id: params[:user_id])
      return api_obj_missing if @user.nil?
    end
  end

end

