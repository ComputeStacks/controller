class Deployments::EventsController < Deployments::BaseController

  def index
    @logs = @deployment.event_logs.sorted.paginate page: params[:page], per_page: 25
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
    respond_to do |format|
      format.html { render template: 'deployments/events/last_event', layout: false }
      format.json { render json: @last_event }
    end
  end

end
