class AlertNotificationsController < AuthController

  include RescueResponder

  before_action :find_alert_notification, only: %i[show update]

  def index
    unless request.xhr?
      @alerts = current_user.alert_notifications.recent.resolved.sorted.paginate(page: params[:page], per_page: 15)
      @events = current_user.event_logs.failed.recent.sorted
    end
    if params[:page].nil? || params[:page].to_i == 1
      @active_alerts = current_user.alert_notifications.active.sorted
    end
    render(layout: false) if request.xhr?
  end

  def show
    if request.xhr?
      if @alert.can_view? current_user
        render template: 'alert_notifications/show', layout: false
      else
        render pain: '', layout: false
      end
    elsif !@alert.can_view?(current_user)
      not_found_responder
    end
  end

  def update
    @alert.resolve = true
    unless @alert.save
      flash[:alert] = "#{@alert.errors.full_messages.join(' ')}"
    end
    redirect_to "/alert_notifications"
  end

  def status
    @active_alerts = current_user.alert_notifications.active.exists?
    render layout: false
  end

  private

  def alert_params
    params.require(:alert_notification).permit(:resolve)
  end

  def find_alert_notification
    @alert = AlertNotification.find(params[:id])
  end

  def not_found_responder
    redirect_to "/deployments", alert: "Unknown Alert"
  end

end
