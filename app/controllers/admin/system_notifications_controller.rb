class Admin::SystemNotificationsController < Admin::ApplicationController

  include RescueResponder

  before_action :find_notification, except: %i[index new create]

  def index
    @notifications = SystemNotification.sorted
  end

  def new
    @notification = SystemNotification.new
  end

  def show
    redirect_to action: :edit
  end

  def edit; end

  def create
    if params[:all]
      SystemNotification.create_all!
      redirect_to admin_system_notifications_path, success: 'All Notification Rules Created'
    else
      @notification = SystemNotification.new notification_params
      if @notification.save
        redirect_to "/admin/system_notifications", success: 'Notification created'
      else
        render template: 'admin/system_notifications/new'
      end
    end
  end

  def update
    if @notification.update(notification_params)
      redirect_to "/admin/system_notifications", success: 'Notification updated'
    else
      render template: 'admin/system_notifications/edit'
    end
  end

  def destroy
    if @notification.destroy
      redirect_to "/admin/system_notifications", success: 'Notification destroyed'
    else
      redirect_to admin_system_notification_path(@notification), alert: @notification.errors.full_messages.join(' ')
    end
  end

  private

  def notification_params
    params.require(:system_notification).permit(:label, :notifier, :value, rules: [])
  end

  def find_notification
    @notification = SystemNotification.find params[:id]
  end

  def not_found_responder
    redirect_to admin_system_notifications_path, alert: "Unknown alert"
  end

end
