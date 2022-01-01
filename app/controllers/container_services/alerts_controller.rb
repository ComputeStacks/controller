class ContainerServices::AlertsController < ContainerServices::BaseController

  def index
    if request.xhr?
      @alerts = @service.alert_notifications.active.sorted
      render template: 'alert_notifications/resource_alert', layout: false
    end
  end

end
