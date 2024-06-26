class Admin::Volumes::BackupsController < Admin::Volumes::BaseController

  before_action :can_perform?, only: %i[create destroy]

  def index
    if request.xhr?
      render template: "volumes/backups/index", layout: false
    else
      redirect_to helpers.volume_path(@volume)
    end
  end

  def show
    redirect_to helpers.volume_path(@volume)
  end

  def create
    if params[:name].length < 3
      redirect_to helpers.volume_path(@volume), alert: "Name too short, must be at least 3 characters."
      return false
    end
    audit = Audit.create_from_object!(@volume, 'backup.create', request.remote_ip, current_user)
    @volume.current_audit = audit

    event = @volume.event_logs.create!(
      locale: 'volume.backup',
      locale_keys: {},
      status: 'pending',
      audit: audit,
      event_code: 'agent-ad28e9aa1933495f'
    )
    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    if @volume.create_backup!(params[:name])
      flash[:success] = "Backup will be created shortly"
    else
      event.fail! "Fatal Error"
      flash[:alert] = "Failed to create backup, check volume event logs."
    end
    redirect_to helpers.volume_path(@volume)
  end

  def destroy
    name = Base64.decode64(params[:id])
    if name.blank?
      redirect_to helpers.volume_path(@volume), alert: "Unknown backup."
      return false
    end
    audit = Audit.create_from_object!(@volume, 'backup.delete', request.remote_ip, current_user)
    @volume.current_audit = audit

    event = @volume.event_logs.create!(
      locale: 'backup.delete',
      locale_keys: {},
      status: 'pending',
      audit: audit,
      event_code: 'agent-1105683bb0f948c0'
    )
    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    if @volume.delete_backup!(name)
      flash[:info] = "Backup will be deleted shortly."
    else
      event.fail! "Fatal error"
      flash[:alert] = "Failed to destroy backup, check volume event logs."
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
