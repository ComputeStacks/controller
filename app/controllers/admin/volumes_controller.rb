# Volumes Controller
class Admin::VolumesController < Admin::ApplicationController

  before_action :find_vol, only: %w(show edit update)
  before_action :find_services, only: %w(edit update)

  def index
    volumes = Volume.where(to_trash: params[:state] == 'trashed')
    volumes = case params[:containers]
              when 'linked'
                volumes.left_outer_joins(:volume_maps).where.not(volume_maps: {id: nil})
              when 'unlinked'
                volumes.where.missing(:volume_maps)
              else
                volumes
              end

    volumes = case params[:user]
              when 'user'
                volumes.where.not(user: nil)
              when 'nouser'
                volumes.where(user: nil)
              else
                volumes
              end
    volumes = case params[:region].to_i
              when 0
                volumes
              else
                volumes.where(region_id: params[:region])
              end
    @volumes = volumes.sorted.paginate per_page: 25, page: params[:page]
  end

  def show; end

  def edit; end

  def update
    if @volume.update(volume_params)
      redirect_to "/admin/volumes/#{@volume.id}"
    else
      render template: 'admin/volumes/edit'
    end
  end

  def create
    @volume = Volume.new(volume_params)
    @services = Deployment::ContainerService.all
    service = Deployment::ContainerService.find_by(id: volume_params[:container_service_id])
    if service.nil?
      @volume.errors.add(:container_service_id, 'is missing.')
      render template: 'admin/volumes/new'
      return false
    end
    @volume.region = service.region
    if @volume.save
      redirect_to "/admin/volumes/#{@volume.id}", notice: "Volume created."
    else
      render template: 'admin/volumes/new'
    end
  end

  def destroy
    volume_ids = []
    volume_ids << params[:id] if params[:id]
    volume_ids = volume_ids + params[:volume_ids] if params[:volume_ids].is_a?(Array)
    volume_ids.flatten!
    if volume_ids.empty?
      redirect_to "/admin/volumes", alert: "No volumes selected."
      return false
    end
    volume_ids.each do |i|
      vol = Volume.find_by(id: i)
      next if vol.nil?
      audit = Audit.create_from_object!(vol, 'deleted', request.remote_ip, current_user)
      audit.update_attribute :raw_data, { name: vol.name }
      vol.update to_trash: true, trashed_by: audit
    end
    redirect_to "/admin/volumes", notice: "#{volume_ids.count} volumes queued for deletion."
  end

  private

  def volume_params
    params.require(:volume).permit(
      :label, :container_service_id, :to_trash, :region_id,
      :borg_freq, :borg_strategy, :borg_backup_error, :borg_restore_error,
      :borg_keep_hourly, :borg_keep_daily, :borg_keep_weekly, :borg_keep_monthly,
      :borg_pre_backup, :borg_post_backup, :borg_pre_restore, :borg_post_restore,
      :borg_rollback, :to_trash, :volume_backend, :borg_enabled, :borg_keep_annually
    )
  end

  def find_vol
    @volume = Volume.find_by(id: params[:id])
    return redirect_to "/admin/volumes", alert: "Unknown volume." if @volume.nil?
    @deployment = @volume.deployment
    @back_url = case params[:from]
                when 'deployment'
                  @deployment ? "/admin/deployments/#{@deployment.id}" : "/admin/volumes"
                else
                  "/admin/volumes"
                end
  end

  def find_services
    @services = @volume.available_services
  end

end
