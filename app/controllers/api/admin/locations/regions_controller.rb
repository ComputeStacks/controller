##
# # Regions
class Api::Admin::Locations::RegionsController < Api::Admin::Locations::BaseController

  before_action :find_region, except: %i[ index create ]

  ##
  # List All Regions
  #
  # `GET /api/admin/locations/{location_id}/regions`
  #
  # * `regions`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `active`: Boolean
  #     * `fill_to`: Integer
  #     * `volume_backend`: String - local or nfs
  #     * `nfs_remote_host`: String - IP Address of NFS server when connecting from the node
  #     * `nfs_remote_path`: String - path to nfs volume on remote server. the volume name will be appended to this, so dont add trailing slash.
  #     * `nfs_controller_ip`: String - IP Address of NFS Server when connecting from the controller
  #     * `offline_window`: Integer - In seconds, how long do we wait after the last heartbeat before consider this node offline?
  #     * `failure_count`: Integer - How many times do we attempt to connect back to the node to verify it's really offline before migrating it's containers to other nodes
  #     * `loki_endpoint`: String
  #     * `loki_retries`: String
  #     * `loki_batch_size`: String
  #     * `loki_client_id`: Integer
  #     * `metric_client_id`: Integer
  #     * `pid_limit`: Integer (0 = unlimited)
  #     * `ulimit_nofile_soft`: Integer (0 = unlimited)
  #     * `ulimit_nofile_hard`: Integer (0 = unlimited)
  #     * `disable_oom`: Boolean (default: false) Disable OomKiller. Warning, process may freeze and require manual intervention.
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @regions = @location.regions.sorted
    respond_to :json, :xml
  end

  ##
  # View Region
  #
  # `GET /api/admin/locations/{location_id}/regions/{id}`
  #
  # * `regions`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `active`: Boolean
  #     * `fill_to`: Integer
  #     * `volume_backend`: String - local or nfs
  #     * `nfs_remote_host`: String - IP Address of NFS server when connecting from the node
  #     * `nfs_remote_path`: String - path to nfs volume on remote server. the volume name will be appended to this, so dont add trailing slash.
  #     * `nfs_controller_ip`: String - IP Address of NFS Server when connecting from the controller
  #     * `offline_window`: Integer - In seconds, how long do we wait after the last heartbeat before consider this node offline?
  #     * `failure_count`: Integer - How many times do we attempt to connect back to the node to verify it's really offline before migrating it's containers to other nodes
  #     * `loki_endpoint`: String
  #     * `loki_retries`: String
  #     * `loki_batch_size`: String
  #     * `loki_client_id`: Integer
  #     * `metric_client_id`: Integer
  #     * `pid_limit`: Integer (0 = unlimited)
  #     * `ulimit_nofile_soft`: Integer (0 = unlimited)
  #     * `ulimit_nofile_hard`: Integer (0 = unlimited)
  #     * `disable_oom`: Boolean (default: false) Disable OomKiller. Warning, process may freeze and require manual intervention.
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show
    respond_to :json, :xml
  end

  ##
  # Update Region
  #
  # `PATCH /api/admin/locations/{location_id}/regions/{id}`
  #
  # _Note: You may not update the name of an existing region. In a future update we will make that change possible._
  #
  # * `regions`: Array
  #     * `active`: Boolean
  #     * `fill_to`: Integer
  #     * `volume_backend`: String - local or nfs
  #     * `nfs_remote_host`: String - IP Address of NFS server when connecting from the node
  #     * `nfs_remote_path`: String - path to nfs volume on remote server. the volume name will be appended to this, so dont add trailing slash.
  #     * `nfs_controller_ip`: String - IP Address of NFS Server when connecting from the controller
  #     * `offline_window`: Integer - In seconds, how long do we wait after the last heartbeat before consider this node offline?
  #     * `failure_count`: Integer - How many times do we attempt to connect back to the node to verify it's really offline before migrating it's containers to other nodes
  #     * `loki_endpoint`: String
  #     * `loki_retries`: String
  #     * `loki_batch_size`: String
  #     * `loki_client_id`: Integer
  #     * `metric_client_id`: Integer
  #     * `pid_limit`: Integer (0 = unlimited)
  #     * `ulimit_nofile_soft`: Integer (0 = unlimited)
  #     * `ulimit_nofile_hard`: Integer (0 = unlimited)
  #     * `disable_oom`: Boolean (default: false) Disable OomKiller. Warning, process may freeze and require manual intervention.
  #
  def update
    return api_obj_error(@region.errors.full_messages) unless @region.update(region_update_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create Region
  #
  # `POST /api/admin/locations/{location_id}/regions`
  #
  # * `regions`: Object
  #     * `active`: Boolean
  #     * `fill_to`: Integer
  #     * `volume_backend`: String - local or nfs
  #     * `nfs_remote_host`: String - IP Address of NFS server when connecting from the node
  #     * `nfs_remote_path`: String - path to nfs volume on remote server. the volume name will be appended to this, so dont add trailing slash.
  #     * `nfs_controller_ip`: String - IP Address of NFS Server when connecting from the controller
  #     * `offline_window`: Integer - In seconds, how long do we wait after the last heartbeat before consider this node offline?
  #     * `failure_count`: Integer - How many times do we attempt to connect back to the node to verify it's really offline before migrating it's containers to other nodes
  #     * `loki_endpoint`: String
  #     * `loki_retries`: String
  #     * `loki_batch_size`: String
  #     * `loki_client_id`: Integer
  #     * `metric_client_id`: Integer
  #     * `pid_limit`: Integer (0 = unlimited)
  #     * `ulimit_nofile_soft`: Integer (0 = unlimited)
  #     * `ulimit_nofile_hard`: Integer (0 = unlimited)
  #     * `disable_oom`: Boolean (default: false) Disable OomKiller. Warning, process may freeze and require manual intervention.
  #
  def create
    @region = @location.regions.new region_create_params
    @region.current_user = current_user
    return api_obj_error(@region.errors.full_messages) unless @region.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete Region
  #
  # `DELETE /api/admin/locations/{location_id}/regions/{id}`
  #
  def destroy
    return api_obj_error(@region.errors.full_messages) unless @region.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def region_create_params
    params.require(:region).permit(
      :name, :active, :fill_to, :metric_client_id, :loki_endpoint, :log_client_id, :loki_retries, :loki_batch_size,
      :volume_backend, :nfs_remote_host, :nfs_remote_path, :offline_window, :failure_count, :nfs_controller_ip,
      :ulimit_nofile_soft, :ulimit_nofile_hard, :pids_limit, :disable_oom
    )
  end

  def region_update_params
    params.require(:region).permit(
      :active, :fill_to, :metric_client_id, :loki_endpoint, :log_client_id, :loki_retries, :loki_batch_size,
      :volume_backend, :nfs_remote_host, :nfs_remote_path, :offline_window, :failure_count, :nfs_controller_ip,
      :ulimit_nofile_soft, :ulimit_nofile_hard, :pids_limit, :disable_oom
    )
  end

  def find_region
    @region = @location.regions.find_by id: params[:id]
    return api_obj_missing if @region.nil?
    @region.current_user = current_user
  end

end
