class Deployments::NotificationRulesController < Deployments::BaseController

  include RescueResponder

  before_action :find_notification, except: %i[index new create]

  def index
    @notifications = @deployment.project_notifiers.sorted
  end

  def new
    @notification = @deployment.project_notifiers.new deployment: @deployment
  end

  def edit; end

  def show
    redirect_to action: :edit
  end

  def create
    @notification = @deployment.project_notifiers.new notification_params
    @notification.deployment = @deployment
    if @notification.save
      redirect_to deployment_notification_rules_path(@deployment), success: 'Notification created'
    else
      render template: 'deployments/notification_rules/new'
    end
  end

  def update
    if @notification.update(notification_params)
      redirect_to deployment_notification_rules_path(@deployment), success: 'Notification updated'
    else
      render template: 'deployments/notification_rules/edit'
    end
  end

  def destroy
    if @notification.destroy
      redirect_to deployment_notification_rules_path(@deployment), success: 'Notification destroyed'
    else
      redirect_to deployment_notification_rules_path(@deployment), alert: @notification.errors.full_messages.join(' ')
    end
  end

  private

  def notification_params
    params.require(:project_notification).permit(:label, :notifier, :value, rules: [])
  end

  def find_notification
    @notification = @deployment.project_notifiers.find params[:id]
  end

  def not_found_responder
    redirect_to deployment_notification_rules_path(@deployment), alert: "Unknown alert"
  end

end
