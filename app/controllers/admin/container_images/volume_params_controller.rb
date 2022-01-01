class Admin::ContainerImages::VolumeParamsController < Admin::ApplicationController

  before_action :find_image
  before_action :find_volume, only: %i[edit update destroy]

  def new
    @volume = @image.volumes.new
    if Feature.check('backups', current_user)
      @volume.borg_enabled = true
      @volume.borg_freq = '@daily'
      @volume.borg_strategy = 'file'
      @volume.borg_keep_hourly = 1
      @volume.borg_keep_daily = 3
      @volume.borg_keep_weekly = 2
      @volume.borg_keep_monthly = 1
    end
    render template: "container_images/volume_params/new"
  end

  def edit
    render template: "container_images/volume_params/edit"
  end

  def create
    @volume = @image.volumes.new(volume_params)
    if @volume.save
      redirect_to helpers.container_image_path(@image), success: "Volume added"
    else
      render template: "container_images/volume_params/new"
    end
  end

  def update

    if @volume.update(volume_params)
      redirect_to helpers.container_image_path(@image), notice: "Volume updated"
    else
      render template: "container_images/volume_params/edit"
    end

  end

  def destroy
    if @volume.destroy
      redirect_to helpers.container_image_path(@image), success: "Volume removed"
    else
      redirect_to helpers.container_image_path(@image), alert: "Failed to delete: #{@volume.errors.full_messages.join(' ')}"
    end
  end

  private

  def find_image
    @image = ContainerImage.find_by(id: params[:container_image_id])
    if @image.nil?
      redirect_to "/container_images", alert: "image not found."
      return false
    end
  end

  def volume_params
    params.require(:container_image_volume_param).permit(
      :mount_path, :label, :enable_sftp, :borg_enabled, :borg_freq, :borg_strategy,
      :borg_keep_hourly, :borg_keep_daily, :borg_keep_weekly, :borg_keep_monthly, :borg_backup_error,
      :borg_restore_error, borg_pre_backup: [], borg_post_backup: [], borg_pre_restore: [],
      borg_post_restore: [], borg_rollback: []
    )
  end

  def find_volume
    @volume = @image.volumes.find_by(id: params[:id])
    if @volume.nil?
      redirect_to helpers.container_image_path(@image), alert: "Volume not found."
      return false
    end
    @volume.current_user = current_user
  end

end
