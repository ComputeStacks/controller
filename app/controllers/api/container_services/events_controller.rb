##
# Service Events
class Api::ContainerServices::EventsController < Api::ContainerServices::BaseController

  ##
  # List Events
  #
  # `GET /api/container_services/{container-service-id}/events`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `event_logs`: Array<EventLog>
  #
  def index
    @events = @service.event_logs.sorted
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/event_logs/index' }
    end
  end


  ##
  # View Event
  #
  # `GET /api/container_services/{container-service-id}/events/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `event_logs`: Object<EventLog>
  #
  def show
    @event = @service.event_logs.find_by(id: params[:id])
    return api_obj_missing if @event.nil?
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/event_logs/show' }
    end
  end

end
