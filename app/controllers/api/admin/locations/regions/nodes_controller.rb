##
# # Nodes
class Api::Admin::Locations::Regions::NodesController < Api::Admin::Locations::Regions::BaseController

  before_action :find_node, except: %i[ index create ]

  ##
  # List All Nodes
  #
  # `GET /api/admin/locations/{location_id}/regions/{region_id}/nodes`
  #
  # * `nodes`: Array
  #     * `id`: String
  #     * `label`: String
  #     * `hostname`: String
  #     * `primary_ip`: String
  #     * `disconnected`: Boolean
  #     * `failed_health_checks`: Integer
  #     * `active`: Boolean
  #     * `online_at`: DateTime
  #     * `disconnected_at`: DateTime
  #     * `public_ip`: String
  #     * `region_id`: Integer
  #     * `maintenance`: Boolean
  #     * `maintenance_updated`: DateTime
  #     * `job_status`: String
  #     * `ssh_port`: Integer
  #     * `volume_device`: String
  #     * `block_write_bps`: Integer (0 = unlimited)
  #     * `block_read_bps`: Integer (0 = unlimited)
  #     * `block_read_ios`: Integer (0 = unlimited)
  #     * `block_write_iops`: Integer (0 = unlimited)
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @nodes = @region.nodes.sorted
    respond_to :json, :xml
  end

  ##
  # View Node
  #
  # `GET /api/admin/locations/{location_id}/regions/{region_id}/nodes/{id}`
  #
  # * `node`: Object
  #     * `id`: String
  #     * `label`: String
  #     * `hostname`: String
  #     * `primary_ip`: String
  #     * `disconnected`: Boolean
  #     * `failed_health_checks`: Integer
  #     * `active`: Boolean
  #     * `online_at`: DateTime
  #     * `disconnected_at`: DateTime
  #     * `public_ip`: String
  #     * `region_id`: Integer
  #     * `maintenance`: Boolean
  #     * `maintenance_updated`: DateTime
  #     * `job_status`: String
  #     * `ssh_port`: Integer
  #     * `volume_device`: String
  #     * `block_write_bps`: Integer (0 = unlimited)
  #     * `block_read_bps`: Integer (0 = unlimited)
  #     * `block_read_ios`: Integer (0 = unlimited)
  #     * `block_write_iops`: Integer (0 = unlimited)
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show
    respond_to :json, :xml
  end

  ##
  # Update Node
  #
  # `PATCH /api/admin/locations/{location_id}/regions/{region_id}/nodes/{id}`
  #
  # _Note: We currently do not allow changing the hostname of an existing node._
  #
  # * `node`: Object
  #     * `label`: String
  #     * `primary_ip`: String
  #     * `active`: Boolean
  #     * `public_ip`: String
  #     * `region_id`: Integer
  #     * `ssh_port`: Integer
  #     * `volume_device`: String
  #     * `block_write_bps`: Integer (0 = unlimited)
  #     * `block_read_bps`: Integer (0 = unlimited)
  #     * `block_read_ios`: Integer (0 = unlimited)
  #     * `block_write_iops`: Integer (0 = unlimited)
  #
  def update
    return api_obj_error(@node.errors.full_messages) unless @node.update(node_update_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create Node
  #
  # `POST /api/admin/locations/{location_id}/regions/{region_id}/nodes`
  #
  # * `node`: Object
  #     * `label`: String
  #     * `primary_ip`: String
  #     * `active`: Boolean
  #     * `public_ip`: String
  #     * `region_id`: Integer
  #     * `ssh_port`: Integer
  #     * `volume_device`: String
  #     * `block_write_bps`: Integer (0 = unlimited)
  #     * `block_read_bps`: Integer (0 = unlimited)
  #     * `block_read_ios`: Integer (0 = unlimited)
  #     * `block_write_iops`: Integer (0 = unlimited)
  #
  def create
    @node = @region.nodes.new node_create_params
    @node.current_user = current_user
    return api_obj_error(@node.errors.full_messages) unless @node.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete Node
  #
  # `DELETE /api/admin/locations/{location_id}/regions/{region_id}/nodes/{id}`

  def destroy
    return api_obj_error(@region.errors.full_messages) unless @region.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def node_create_params
    params.require(:node).permit(
      :label, :hostname, :primary_ip, :active, :public_ip,
      :volume_device, :block_write_bps, :block_read_bps, :block_write_iops, :block_read_iops
    )
  end

  def node_update_params
    params.require(:node).permit(
      :label, :primary_ip, :active, :public_ip, :volume_device,
      :block_write_bps, :block_read_bps, :block_write_iops, :block_read_iops
    )
  end

  def find_node
    @node = @region.nodes.find_by id: params[:id]
    return api_obj_missing if @node.nil?
    @node.current_user = current_user
  end

end
