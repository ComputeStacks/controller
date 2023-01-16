class Deployments::EventsController < Deployments::BaseController

  def index
    if request.xhr?
      @logs = @deployment.event_logs.sorted.paginate page: params[:page], per_page: 25
      @root_path = "/deployments/#{@deployment.token}/events"
      render template: 'event_logs/list', layout: false
    end
  end

  def show
    @log = @deployment.event_logs.find_by(id: params[:id])
    if @log.nil?
      redirect_to "/deployments/#{@deployment.token}", alert: "Unknown"
      return false
    end
    @subscribers = @log.subscribers(current_user)
  end

  def last_event
    @last_event = @deployment.last_event
    @active_events = @deployment.event_logs.running.count
    respond_to do |format|
      format.html { render template: 'deployments/events/last_event', layout: false }
      format.json { render json: @last_event }
    end
  end

end
