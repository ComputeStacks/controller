class Admin::AlertNotificationsController < Admin::ApplicationController

  include RescueResponder

  before_action :find_alert_notification, only: %i[show update]

  def index
    unless request.xhr?
      @alerts = AlertNotification.recent.resolved.sorted.paginate(page: params[:page], per_page: 15)
    end
    if params[:page].nil? || params[:page].to_i == 1
      @active_alerts = AlertNotification.active.sorted
    end
    render(layout: false) if request.xhr?
  end

  def show
    if request.xhr?
      render template: 'admin/alert_notifications/show', layout: false
    end
  end

  def update
    @alert.resolve = true
    unless @alert.save
      flash[:alert] = "#{@alert.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/alert_notifications"
  end

  def status
    @active_alerts = AlertNotification.active.exists?
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
    redirect_to "/admin/alert_notifications", alert: "Unknown Alert"
  end

end
