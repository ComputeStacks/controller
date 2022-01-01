class UserNotificationsController < AuthController

  include RescueResponder

  before_action :find_notification, except: %i[index new create]

  def index
    @notifications = current_user.user_notifications.sorted
    @project_notifications = current_user.deployments.joins(:project_notifiers)
  end

  def new
    @notification = current_user.user_notifications.new
  end

  def show
    redirect_to action: :edit
  end

  def edit; end

  def create
    @notification = current_user.user_notifications.new notification_params
    if @notification.save
      redirect_to "/user_notifications", success: 'Notification created'
    else
      render template: 'user_notifications/new'
    end
  end

  def update
    if @notification.update(notification_params)
      redirect_to "/user_notifications", success: 'Notification updated'
    else
      render template: 'user_notifications/edit'
    end
  end

  def destroy
    if @notification.destroy
      redirect_to "/user_notifications", success: 'Notification destroyed'
    else
      redirect_to user_notification_path(@notification), alert: @notification.errors.full_messages.join(' ')
    end
  end

  private

  def notification_params
    params.require(:user_notification).permit(:label, :notifier, :value, rules: [])
  end

  def find_notification
    @notification = current_user.user_notifications.find params[:id]
  end

  def not_found_responder
    redirect_to "/user_notifications", alert: "Unknown notification"
  end

end
