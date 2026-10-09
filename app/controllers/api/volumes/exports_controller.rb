##
# Export a Volume Backup (generate a presigned download URL)
class Api::Volumes::ExportsController < Api::Volumes::BaseController
  before_action :can_perform?, only: %i[create]

  ##
  # Request a backup export
  #
  # `POST /volumes/{volume-id}/exports`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  # * `id`: String | urlsafe base64 encoded name of the backup to export
  # * `callback`: Object | optional webhook to call after the export is finished
  #     * `authorization`: String | Right side of authorization header. Example: `Bearer 12345` or `Token 12345`
  #     * `url`: String | fully qualified URL
  #
  # The presigned URL is not returned here. Poll `GET /volumes/{volume-id}/backups`
  # (each archive carries an `export` object with `status`/`url`/`expires_at`) or
  # supply a `callback` to be notified when it is ready.
  # If the volume's node is in maintenance or offline (or the volume has no node), the
  # event is failed and the response is `409 Conflict` with `errors`, `code`
  # (`node_maintenance` or `node_offline`) and `node_status`; any callback reports the
  # failure. Other failures are `422 Unprocessable Entity` with `errors`.
  #
  def create
    archive = decoded_archive
    return api_obj_error(["Missing backup name"]) if archive.blank?

    audit = Audit.create_from_object!(@volume, "backup.export", request.remote_ip, current_user)
    @volume.current_audit = audit

    event = EventLog.new(
      locale: "volume.download",
      locale_keys: {},
      status: "pending",
      audit: audit,
      event_code: EventLog::BACKUP_EXPORT_EVENT_CODE,
      labels: {"archive" => archive}
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

    jid = @volume.export_backup!(archive)
    unless jid
      event.fail!(@volume.dispatch_error || "Fatal Error", code: @volume.dispatch_error_code)
      if @volume.dispatch_error_code
        return api_node_unavailable([@volume.dispatch_error], code: @volume.dispatch_error_code,
          node_status: Nodes::CustomerStatusPresenter.rollup(@volume.nodes))
      end
      return api_obj_error([@volume.dispatch_error || "Failed to start export. Check volume event logs."])
    end
    event.update(labels: event.labels.merge("task_id" => jid))

    respond_to do |format|
      format.json { render json: {}, status: :accepted }
      format.xml { render xml: {}, status: :accepted }
    end
  end

  private

  def decoded_archive
    Base64.urlsafe_decode64(params[:id].to_s)
  rescue ArgumentError
    ""
  end

  # One export at a time per volume (best-effort; the export does not lock the repo).
  def can_perform?
    if @volume.event_logs.active.where(event_code: EventLog::BACKUP_EXPORT_EVENT_CODE).exists?
      respond_to do |format|
        format.json { render json: {errors: ["A download is already being prepared for this volume."]}, status: :method_not_allowed }
        format.xml { render xml: {errors: ["A download is already being prepared for this volume."]}, status: :method_not_allowed }
      end
    end
  end
end
