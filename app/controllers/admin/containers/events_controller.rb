class Admin::Containers::EventsController < Admin::Containers::BaseController

  def index
    @logs = @container.event_logs.sorted.limit(50)
    render template: 'admin/event_logs/shared/list', layout: false
  end

end
