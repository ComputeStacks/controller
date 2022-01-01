class EventLogsController < AuthController

  def show
    @event = EventLog.find_for_user(params[:id], current_user)
    if @event.nil?
      redirect_to "/deployments", alert: "Unknown event"
    else
      @subscribers = @event.subscribers(current_user)
    end
  end

end
