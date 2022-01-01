class VolumesController < AuthController

  before_action :find_volume, only: %w(show edit update destroy)

  def index
    @volumes = Volume.find_all_for(current_user).where(to_trash: false)
  end

  def show; end

  def new
    redirect_to("/deployments")
  end

  def edit; end

  def update
    audit = Audit.create_from_object!(@volume, 'updated', request.remote_ip, current_user)
    @volume.current_audit = audit
    @volume.force_rebuild = true
    if @volume.update(volume_params)
      redirect_to "/volumes/#{@volume.id}", notice: "Volume updated"
    else
      audit.destroy
      render template: "volumes/edit"
    end
  end

  def destroy
    audit = Audit.create_from_object!(@volume, 'deleted', request.remote_ip, current_user)
    if @volume.update(to_trash: true, trashed_by: audit)
      flash[:notice] = "Volume will be deleted shortly."
    else
      flash[:alert] = "Error: #{@volume.errors.full_messages.join(' ')}"
    end
    redirect_to @base_url
  end

  private

  def volume_params
    params.require(:volume).permit(
      :label, :container_service_id, :to_trash, :container_path,
      :borg_freq, :borg_strategy, :borg_backup_error, :borg_restore_error,
      :borg_keep_hourly, :borg_keep_daily, :borg_keep_weekly, :borg_keep_monthly,
      :borg_pre_backup, :borg_post_backup, :borg_pre_restore, :borg_post_restore,
      :borg_rollback, :borg_enabled
    )
  end

  def find_volume
    @volume = Volume.find_for current_user, { id: params[:id] }
    return(redirect_to("/volumes", alert: "Unknown Volume")) if @volume.nil?
    @deployment = @volume.deployment
    @base_url = @deployment.nil? ? "/volumes/#{@volume.id}" : "/deployments/#{@deployment.token}"
  end

end
