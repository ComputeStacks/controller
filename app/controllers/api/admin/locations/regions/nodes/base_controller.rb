class Api::Admin::Locations::Regions::Nodes::BaseController < Api::Admin::Locations::Regions::BaseController

  before_action :find_node

  private

  def find_node
    @node = @region.nodes.find_by id: params[:node_id]
    return api_obj_missing if @node.nil?
    @node.current_user = current_user
  end

end
