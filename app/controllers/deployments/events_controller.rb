class Deployments::EventsController < Deployments::BaseController
  def index
    if request.xhr?
      @logs = @deployment.event_logs.sorted.paginate page: params[:page], per_page: 25
      @root_path = "/deployments/#{@deployment.token}/events"
      render template: "event_logs/list", layout: false
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
    # `active`, not `running`: a clone's umbrella event is created pending and a queued
    # backup/restore child event sits pending until the agent picks it up, so counting only
    # `running` reads as "nothing is happening" while work is very much outstanding.
    @active_events = @deployment.event_logs.active.count
    respond_to do |format|
      format.html { render template: "deployments/events/last_event", layout: false }
      format.json { render json: @last_event }
    end
  end
end
