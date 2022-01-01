class Admin::Nodes::EventsController < Admin::Nodes::BaseController

  def index
    @logs = @node.event_logs.sorted.paginate(per_page: 30, page: params[:page])
  end

  def show
    @log = @node.event_logs.find_by(id: params[:id])
    if @log.nil?
      redirect_to "/admin/nodes/#{@node.id}/events", alert: "Unknown Event."
      return false
    end
    @subscribers = @log.subscribers(current_user)
  end

end