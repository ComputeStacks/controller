class Admin::Deployments::Services::EventsController < Admin::Deployments::Services::BaseController

  def index
    @logs = @service.event_logs.sorted
    render template: 'admin/event_logs/shared/list', layout: false
  end

end