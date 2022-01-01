class Admin::Nodes::BaseController < Admin::ApplicationController

  before_action :find_node

  private

  def find_node
    @node = Node.find_by(id: params[:node_id])
    return redirect_to("/admin/nodes", alert: "Node not found.") if @node.nil?
  end

end