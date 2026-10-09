##
# # Nodes
class Api::Admin::Locations::Regions::NodesController < Api::Admin::Locations::Regions::BaseController
  before_action :find_node, except: %i[index create]

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
  #     * `agent_host`: String (optional; cs-agent address, defaults to primary_ip)
  #     * `disconnected`: Boolean
  #     * `failed_health_checks`: Integer
  #     * `active`: Boolean
  #     * `online_at`: DateTime
  #     * `disconnected_at`: DateTime
  #     * `public_ip`: String
  #     * `region_id`: Integer
  #     * `maintenance`: Boolean - effective maintenance: the controller's hold OR the node's own
  #     * `maintenance_updated`: DateTime - when the controller hold last changed
  #     * `maintenance_status`: Object - read from stored state; never calls the agent
  #         * `effective`: Boolean - same as `maintenance`
  #         * `requested`: Boolean - the controller hold
  #         * `reason`: String - reason given with the controller hold
  #         * `requested_at`: DateTime | null
  #         * `gen`: Integer - generation of the controller hold
  #         * `holds`: Object - as the agent last reported them (`since` in unix seconds)
  #             * `controller`: Object | null - `since`, `reason`, `gen`
  #             * `local`: Object | null - `since`, `reason`, `by` (`cs-agent maintenance on`)
  #         * `paused_since`: DateTime | null
  #         * `skipped_backups`: Integer
  #         * `sample`: Object | null - `quiesce` (quiesced, busy, unknown), `running_count`, `pending`, `sampled_at` (unix seconds)
  #         * `agent`: Object - `supported` (Boolean, agent >= 3.4), `observed_at`, `instance_id`
  #         * `running`: Array - work running on the node at the last status check (`id`, `kind`, `volume`, `started_at`)
  #         * `pending`: Integer
  #         * `warnings`: Array<String> - any of `mismatch`, `stale_hold`, `unsupported_agent`, `status_stale`, `override_pending`
  #     * `job_status`: String
  #     * `ssh_port`: Integer
  #     * `volume_device`: String
  #     * `block_write_bps`: Integer (0 = unlimited)
  #     * `block_read_bps`: Integer (0 = unlimited)
  #     * `block_read_ios`: Integer (0 = unlimited)
  #     * `block_write_iops`: Integer (0 = unlimited)
  #     * `customer_notice`: String | null - message shown to customers while the node is not online
  #     * `customer_status`: Object - what customers see for this node, as `node_status`
  #       on the customer API (`state`, `since`, `planned`, `message`, `operations`)
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
  #     * `agent_host`: String (optional; cs-agent address, defaults to primary_ip)
  #     * `disconnected`: Boolean
  #     * `failed_health_checks`: Integer
  #     * `active`: Boolean
  #     * `online_at`: DateTime
  #     * `disconnected_at`: DateTime
  #     * `public_ip`: String
  #     * `region_id`: Integer
  #     * `maintenance`: Boolean - effective maintenance: the controller's hold OR the node's own
  #     * `maintenance_updated`: DateTime - when the controller hold last changed
  #     * `maintenance_status`: Object - read from stored state; never calls the agent
  #         * `effective`: Boolean - same as `maintenance`
  #         * `requested`: Boolean - the controller hold
  #         * `reason`: String - reason given with the controller hold
  #         * `requested_at`: DateTime | null
  #         * `gen`: Integer - generation of the controller hold
  #         * `holds`: Object - as the agent last reported them (`since` in unix seconds)
  #             * `controller`: Object | null - `since`, `reason`, `gen`
  #             * `local`: Object | null - `since`, `reason`, `by` (`cs-agent maintenance on`)
  #         * `paused_since`: DateTime | null
  #         * `skipped_backups`: Integer
  #         * `sample`: Object | null - `quiesce` (quiesced, busy, unknown), `running_count`, `pending`, `sampled_at` (unix seconds)
  #         * `agent`: Object - `supported` (Boolean, agent >= 3.4), `observed_at`, `instance_id`
  #         * `running`: Array - work running on the node at the last status check (`id`, `kind`, `volume`, `started_at`)
  #         * `pending`: Integer
  #         * `warnings`: Array<String> - any of `mismatch`, `stale_hold`, `unsupported_agent`, `status_stale`, `override_pending`
  #     * `job_status`: String
  #     * `ssh_port`: Integer
  #     * `volume_device`: String
  #     * `block_write_bps`: Integer (0 = unlimited)
  #     * `block_read_bps`: Integer (0 = unlimited)
  #     * `block_read_ios`: Integer (0 = unlimited)
  #     * `block_write_iops`: Integer (0 = unlimited)
  #     * `customer_notice`: String | null - message shown to customers while the node is not online
  #     * `customer_status`: Object - what customers see for this node, as `node_status`
  #       on the customer API (`state`, `since`, `planned`, `message`, `operations`)
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
  #     * `agent_host`: String (optional; cs-agent address, defaults to primary_ip)
  #     * `active`: Boolean
  #     * `public_ip`: String
  #     * `region_id`: Integer
  #     * `ssh_port`: Integer
  #     * `volume_device`: String
  #     * `block_write_bps`: Integer (0 = unlimited)
  #     * `block_read_bps`: Integer (0 = unlimited)
  #     * `block_read_ios`: Integer (0 = unlimited)
  #     * `block_write_iops`: Integer (0 = unlimited)
  #     * `customer_notice`: String (optional) - message to customers with something on this
  #       node, shown in the portal and as `node_status.message` on the API. Plain text.
  #       Can only be set while the node is in maintenance or offline (`422` otherwise); blank
  #       clears it, and it clears itself when the node is back online. Applied before the
  #       other fields, and audited.
  #
  def update
    if params[:node].respond_to?(:key?) && params[:node].key?(:customer_notice)
      notice = NodeServices::CustomerNoticeService.new(
        @node,
        notice: params[:node][:customer_notice],
        actor: current_user,
        remote_ip: request.remote_ip
      )
      return api_obj_error(notice.errors) unless notice.perform
    end
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
  #     * `agent_host`: String (optional; cs-agent address, defaults to primary_ip)
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
      :label, :hostname, :primary_ip, :agent_host, :active, :public_ip,
      :volume_device, :block_write_bps, :block_read_bps, :block_write_iops, :block_read_iops
    )
  end

  def node_update_params
    params.require(:node).permit(
      :label, :primary_ip, :agent_host, :active, :public_ip, :volume_device,
      :block_write_bps, :block_read_bps, :block_write_iops, :block_read_iops
    )
  end

  def find_node
    @node = @region.nodes.find_by id: params[:id]
    return api_obj_missing if @node.nil?
    @node.current_user = current_user
  end
end
