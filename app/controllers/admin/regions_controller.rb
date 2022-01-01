class Admin::RegionsController < Admin::ApplicationController

  before_action :load_region, except: %w(index new create)

  def index
    @regions = Region.sorted
  end

  def show
    @nodes = @region.nodes.sorted
    if request.xhr?
      @resources = @region.resource_usage
      render template: 'admin/regions/index/resources', layout: false
    end
  end

  def new
    @region = Region.new
  end

  def edit; end

  def update
    if @region.update(region_update_params)
      redirect_to "/admin/regions/#{@region.id}", notice: "#{@region.name} successfully updated."
    else
      render template: "admin/regions/edit"
    end
  end

  def create
    @region = Region.new(region_create_params)
    @region.current_user = current_user
    if @region.valid? && @region.save
      redirect_to "/admin/locations", notice: "#{@region.name} successfully created."
    else
      render template: "admin/regions/new"
    end
  end

  def destroy
    if @region.destroy
      redirect_to "/admin/locations", notice: "#{@region.name} successfully deleted."
    else
      redirect_to "/admin/locations", alert: "#{@region.errors.full_messages.join(', ')}"
    end
  end

  private

  def region_create_params
    params.require(:region).permit(
      :name, :active, :fill_to, :metric_client_id, :loki_endpoint, :log_client_id, :loki_retries, :loki_batch_size,
      :volume_backend, :nfs_remote_host, :nfs_remote_path, :offline_window, :failure_count, :nfs_controller_ip,
      :disable_oom, :pid_limit, :ulimit_nofile_hard, :ulimit_nofile_soft
    )
  end

  def region_update_params
    params.require(:region).permit(
      :active, :fill_to, :metric_client_id, :loki_endpoint, :log_client_id, :loki_retries, :loki_batch_size,
      :volume_backend, :nfs_remote_host, :nfs_remote_path, :offline_window, :failure_count, :nfs_controller_ip,
      :disable_oom, :pid_limit, :ulimit_nofile_hard, :ulimit_nofile_soft
    )
  end

  def load_region
    @region = Region.find_by(id: params[:id])
    if @region.nil?
      redirect_to "/admin/locations", alert: "Unknown Availability Zone."
      return false
    end
    @region.current_user = current_user
  end

end
