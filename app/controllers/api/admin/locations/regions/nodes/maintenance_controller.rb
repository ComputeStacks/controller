##
# # Node Maintenance Status
class Api::Admin::Locations::Regions::Nodes::MaintenanceController < Api::Admin::Locations::Regions::Nodes::BaseController

  ##
  # Enable Maintenance Mode
  #
  # `POST /api/admin/locations/{location_id}/regions/{region_id}/nodes/{node_id}/maintenance`
  #
  # *Warning:* This will evacuate all containers that are not using local volumes to other nodes in the region (Availability-Zone).
  #
  # Returns `HTTP 202 Accepted` if successful.

  def create
    @node.maintenance = true
    @node.maintenance_updated = Time.now
    return api_obj_error(@node.errors.full_messages) unless @node.save
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

  ##
  # Disable Maintenance Mode
  #
  # `DELETE /api/admin/locations/{location_id}/regions/{region_id}/nodes/{node_id}/maintenance`
  #
  # Returns `HTTP 202 Accepted` if successful.

  def destroy
    @node.maintenance = false
    @node.maintenance_updated = Time.now
    @node.job_status = 'idle'
    return api_obj_error(@node.errors.full_messages) unless @node.save
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

end
