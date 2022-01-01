class Containers::AlertsController < ContainerServices::BaseController

  def index
    if request.xhr?
      @alerts = @container.alert_notifications.active.sorted
      render template: 'alert_notifications/resource_alert', layout: false
    end
  end

end
