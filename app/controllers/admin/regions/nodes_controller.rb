class Admin::Regions::NodesController < Admin::ApplicationController
  before_action :load_region

  def index
    @nodes = @region.nodes.sorted
    render template: 'admin/nodes/index', layout: request.xhr? ? false : 'admin/layouts/application'
  end

  private

  def load_region
    @region = Region.find_by(id: params[:region_id])
    if @region.nil?
      redirect_to "/admin/locations", alert: "Unknown Availability Zone."
      return false
    end
  end

end
