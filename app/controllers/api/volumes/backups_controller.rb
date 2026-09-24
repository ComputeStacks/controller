##
# Volume Backups
class Api::Volumes::BackupsController < Api::Volumes::BaseController
  before_action :can_perform?, only: %i[create destroy]

  ##
  # List all backups
  #
  # `GET /api/volumes/{volume-id}/backups`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `usage`: Integer | Size on disk (deduplicated)
  # * `size`: Integer | Expanded total size
  # * `archives`: Array
  #   * `id`: String | base64 encoded name
  #   * `label`: String
  #   * `created`: DateTime
  #
  def index
    statuses = @volume.export_status_map
    archives = @volume.list_archives.map do |a|
      name = begin
        Base64.urlsafe_decode64(a[:id])
      rescue ArgumentError
        nil
      end
      a.merge(export: statuses[name] || {status: "none"})
    end
    data = {
      usage: @volume.backup_usage,
      size: @volume.backup_total_usage,
      archives: archives
    }
    respond_to do |format|
      format.json { render json: data }
      format.xml { render xml: data }
    end
  end

  ##
  # Create a backup
  #
  # `POST /volumes/{volume-id}/backups`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  # * `name`: String | Name of backup. Must be at least 3 characters long, and should not include spaces.
  # * `callback`: Object | optional webhook to call after event is finished
  #     * `authorization`: String | Right side of authorization header. Example: `Bearer 12345` or `Token 12345`
  #     * `url`: String | fully qualified URL
  #
  def create
    audit = Audit.create_from_object!(@volume, "backup.create", request.remote_ip, current_user)
    @volume.current_audit = audit

    if params[:name].length < 3
      return api_obj_error(["Name too short, must be at least 3 characters."])
    end

    event = EventLog.new(
      locale: "volume.backup",
      locale_keys: {},
      status: "pending",
      audit: audit,
      event_code: "agent-ad28e9aa1933495f"
    )
    event.volumes << @volume
    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service if @volume.container_service

    if params[:callback]
      event.labels["callback_auth"] = params[:callback][:authorization]
      event.labels["callback_url"] = params[:callback][:url]
    end

    unless event.save
      return api_obj_error(event.errors.full_messages)
    end

    unless @volume.create_backup!(params[:name])
      event.fail! "Fatal Error"
      return api_obj_error(["Failed to create backup. Check volume event logs."])
    end

    respond_to do |format|
      format.json { render json: {}, status: :created }
      format.xml { render xml: {}, status: :created }
    end
  end

  ##
  # Delete Backup
  #
  # `DELETE /volumes/{volume-id}/backups/:name`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  # * `name`: String | base64 encoded name of backup to delete
  # * `callback`: Object | optional webhook to call after event is finished
  #     * `authorization`: String | Right side of authorization header. Example: `Bearer 12345` or `Token 12345`
  #     * `url`: String | fully qualified URL
  #
  def destroy
    name = Base64.decode64 params[:id]
    return api_obj_error(["Missing backup name"]) if name.blank?
    if export_in_progress?(name)
      return api_obj_error(["Cannot delete a backup while its download is being prepared."])
    end

    audit = Audit.create_from_object!(@volume, "backup.delete", request.remote_ip, current_user)
    @volume.current_audit = audit

    event = EventLog.new(
      locale: "backup.delete",
      locale_keys: {},
      status: "pending",
      audit: audit,
      event_code: "agent-1105683bb0f948c0"
    )

    if params[:callback]
      event.labels["callback_auth"] = params[:callback][:authorization]
      event.labels["callback_url"] = params[:callback][:url]
    end   

    event.volumes << @volume
    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    unless event.save
      return api_obj_error(event.errors.full_messages)
    end

    unless @volume.delete_backup!(name)
      event.fail! "Fatal Error"
      return api_obj_error(["Failed to delete backup. Check volume event logs."])
    end

    respond_to do |format|
      format.json { render json: {}, status: :ok }
      format.xml { render xml: {}, status: :ok }
    end
  end

  private

  def can_perform?
    # A volume awaiting its first mount exists on the node but no container has the bind
    # yet, so backing it up would write a healthy-looking archive containing nothing.
    if @volume.awaiting_mount?
      msg = ["This volume is not mounted by any container yet — it will be available after the service's next rebuild."]
      respond_to do |format|
        format.json { render json: {errors: msg}, status: :method_not_allowed }
        format.xml { render xml: {errors: msg}, status: :method_not_allowed }
      end
      return false
    end
    if @volume.operation_in_progress?
      respond_to do |format|
        format.json { render json: {errors: ["Unable to perform while another operation is in progress."]}, status: :method_not_allowed }
        format.xml { render xml: {errors: ["Unable to perform while another operation is in progress."]}, status: :method_not_allowed }
      end
    end
  end

  def export_in_progress?(archive)
    @volume.event_logs.active
      .where(event_code: EventLog::BACKUP_EXPORT_EVENT_CODE)
      .where("labels ->> 'archive' = ?", archive)
      .exists?
  end
end
