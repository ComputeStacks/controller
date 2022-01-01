class Admin::Deployments::EventsController < Admin::Deployments::BaseController

  def index
    if request.xhr?
      @logs = @deployment.event_logs.sorted.limit(3)
      render template: "admin/deployments/show/events", layout: false
    else
      @logs = @deployment.event_logs.sorted.paginate per_page: 30, page: params[:page]
    end
  end

  def show
    @log = @deployment.event_logs.find_by(id: params[:id])
    if @log.nil?
      redirect_to "#{@base_url}/logs", alert: "Unknown log."
      return false
    end
    @subscribers = @log.subscribers(current_user)
  end

end
