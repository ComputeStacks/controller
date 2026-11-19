class Admin::Users::EventLogsController < Admin::Users::ApplicationController
  def index
    if request.xhr?
      @logs = @user.event_logs.sorted.limit(5)
      render template: "admin/users/show/event_logs", layout: false
    else
      @filter = EventLog::AdminFilter.new(params)
      flash.now[:alert] = "Invalid date range, ignored." if @filter.invalid_range?
      @logs = @filter.apply(@user.event_logs).sorted.paginate per_page: 30, page: params[:page]
      render template: "admin/event_logs/index"
    end
  end
end
