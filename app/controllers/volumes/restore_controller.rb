class Volumes::RestoreController < Volumes::BaseController

  before_action :can_perform?, only: %i[create destroy]

  def update
    if params[:id].blank?
      redirect_to helpers.volume_path(@volume), alert: "Unknown backup."
      return false
    end
    audit = Audit.create_from_object!(@volume, 'backup.restore', request.remote_ip, current_user)
    @volume.current_audit = audit
    name = Base64.decode64(params[:id])

    event = @volume.event_logs.create!(
      locale: 'volume.restore',
      locale_keys: {},
      status: 'pending',
      audit: audit,
      event_code: 'agent-bde07117ae85937d'
    )
    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    if @volume.restore_backup!(name)
      flash[:success] = "Backup will be restored shortly. Follow volume event logs."
    else
      event.fail! "Fatal error"
      flash[:alert] = "Failed to restore backup, check volume event logs."
    end
    redirect_to helpers.volume_path(@volume)
  end

  private

  def can_perform?
    if @volume.operation_in_progress?
      redirect_to helpers.volume_path(@volume), alert: "Unable to perform while another operation is in progress."
      return false
    end
  end


end
