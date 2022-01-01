class Api::Admin::EventLogsController < Api::Admin::ApplicationController

  before_action :find_event, only: :show

  def index
    @events = paginate EventLog.sorted
    respond_to :json, :xml
  end

  def show
    respond_to :json, :xml
  end

  private

  def find_event
    @event = EventLog.find_by(id: params[:id])
    return api_obj_missing if @event.nil?
  end

end
