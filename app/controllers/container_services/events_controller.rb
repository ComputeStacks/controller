class ContainerServices::EventsController < ContainerServices::BaseController

  def index
    if request.xhr?
      @logs = @service.event_logs.sorted.paginate page: params[:page], per_page: 25
      @root_path = "#{helpers.container_service_path(@service)}/events"
      render template: 'event_logs/list', layout: false
    end
  end

  def show
    @log = @service.event_logs.find_by(id: params[:id])
    if @log.nil?
      redirect_to "/container_services/#{@service.id}", alert: I18n.t('crud.unknown', resource: 'Log')
      return false
    end
    @subscribers = @log.subscribers(current_user)
  end

  def last_event
    @last_event = @service.last_event
    @active_events = @service.event_logs.running.count
    respond_to do |format|
      format.html { render template: 'container_services/events/last_event', layout: false }
      format.json { render json: @last_event }
    end
  end

end
