##
# Admin variant of Volumes::ExportsController. Same behaviour; routed under /admin.
class Admin::Volumes::ExportsController < Admin::Volumes::BaseController
  before_action :can_perform?, only: %i[update]

  def update
    archive = decoded_archive
    if archive.blank?
      redirect_to helpers.volume_path(@volume), alert: "Unknown backup."
      return false
    end

    audit = Audit.create_from_object!(@volume, "backup.export", request.remote_ip, current_user)
    @volume.current_audit = audit

    event = @volume.event_logs.create!(
      locale: "volume.download",
      locale_keys: {},
      status: "pending",
      audit: audit,
      event_code: EventLog::BACKUP_EXPORT_EVENT_CODE,
      labels: {"archive" => archive}
    )
    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    jid = @volume.export_backup!(archive)
    if jid
      event.update(labels: event.labels.merge("task_id" => jid))
      flash[:success] = "Preparing your download…"
    else
      event.fail! "Fatal Error"
      flash[:alert] = "Failed to start export, check volume event logs."
    end
    redirect_to helpers.volume_path(@volume)
  end

  private

  def decoded_archive
    Base64.urlsafe_decode64(params[:id].to_s)
  rescue ArgumentError
    ""
  end

  def can_perform?
    if @volume.event_logs.active.where(event_code: EventLog::BACKUP_EXPORT_EVENT_CODE).exists?
      redirect_to helpers.volume_path(@volume), alert: "A download is already being prepared for this volume."
      false
    end
  end
end
