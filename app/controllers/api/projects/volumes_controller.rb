##
# Project Volumes
class Api::Projects::VolumesController < Api::Projects::BaseController
  api_scope read: :project_read

  before_action :load_volume, except: %i[index]

  ##
  # List all volumes
  #
  # `GET /api/projects/{project-id}/volumes`
  #
  # **OAuth AuthorizationRequired**: `project_read`
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
  #     * `awaiting_mount`: Boolean - true while the volume exists but no container has mounted it yet (it mounts at the service's next rebuild; backups are suppressed until then)
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
    @volumes = paginate @deployment.volumes.active
    render template: "api/volumes/index"
  end

  ##
  # View Volume
  #
  # `GET /api/projects/{project-id}/volumes/{id}`
  #
  # **OAuth AuthorizationRequired**: `project_read`
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
  #     * `awaiting_mount`: Boolean - true while the volume exists but no container has mounted it yet (it mounts at the service's next rebuild; backups are suppressed until then)
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
  def show
    render template: "api/volumes/show"
  end

  private

  def load_volume
    @volume = @deployment.volumes.find_by id: params[:id]
    api_obj_missing if @volume.nil? || !@volume.can_view?(current_user)
  end
end
