class Api::System::EventsController < Api::System::BaseController
  before_action :find_event, except: %w[index]

  def index
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/event_logs/index" }
    end
  end

  def show
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/event_logs/show" }
    end
  end

  def update
    if @event.update(event_params)
      @event.perform_callback_reply! if @event.done?
    else
      return api_obj_error(@event.errors.full_messages)
    end

    respond_to do |format|
      format.any(:json, :xml) { render template: "api/event_logs/show" }
    end
  end

  private

  def event_params
    params.require(:event_log).permit(
      :audit_id, :locale, :status, :event_code, local_keys: {},
      deployment_ids: [], container_service_ids: [], volume_ids: [],
      event_details_attributes: [:event_code, :data]
    )
  end

  def find_event
    @event = EventLog.find_by(id: params[:id])
    api_obj_missing if @event.nil?
  end
end
