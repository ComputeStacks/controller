class Admin::Volumes::RestoreController < Admin::Volumes::BaseController
  before_action :can_perform?, only: %i[create destroy]
  # NOTE: `can_perform?` above lists actions this controller does not define -- the only
  # action here is #update -- so it never runs. The mount guard is registered separately so
  # that it actually applies to #update, without changing when `can_perform?` fires.
  before_action :volume_mounted?, only: %i[create update destroy]

  def update
    name = decoded_archive
    if name.blank?
      redirect_to helpers.volume_path(@volume), alert: "Unknown backup."
      return false
    end
    audit = Audit.create_from_object!(@volume, "backup.restore", request.remote_ip, current_user)
    @volume.current_audit = audit

    event = @volume.event_logs.create!(
      locale: "volume.restore",
      locale_keys: {},
      status: "pending",
      audit: audit,
      event_code: "agent-bde07117ae85937d"
    )
    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    if @volume.restore_backup!(name)
      flash[:success] = "Backup will be restored shortly. Follow volume event logs."
    else
      event.fail!(@volume.dispatch_error || "Fatal Error")
      flash[:alert] = @volume.dispatch_error || "Failed to restore backup, check volume event logs."
    end
    redirect_to helpers.volume_path(@volume)
  end

  private

  # Archive ids are urlsafe base64 (see Volume#list_archives).
  def decoded_archive
    Base64.urlsafe_decode64(params[:id].to_s).force_encoding(Encoding::UTF_8)
  rescue ArgumentError
    ""
  end

  def can_perform?
    if @volume.operation_in_progress?
      redirect_to helpers.volume_path(@volume), alert: "Unable to perform while another operation is in progress."
      false
    end
  end

  # A volume awaiting its first mount exists on the node but no container has the bind yet,
  # so a restore into it would report success while the application never sees the data.
  def volume_mounted?
    if @volume.awaiting_mount?
      redirect_to helpers.volume_path(@volume), alert: "This volume is not mounted by any container yet — it will be available after the service's next rebuild."
      false
    end
  end
end
