class Admin::Sftp::EventsController < Admin::Sftp::BaseController

  def index
    @logs = @container.event_logs.sorted
    render template: 'admin/event_logs/shared/list', layout: false
  end

end