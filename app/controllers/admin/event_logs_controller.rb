class Admin::EventLogsController < Admin::ApplicationController
  include RescueResponder

  before_action :find_log, only: :show

  def index
    @filter = EventLog::AdminFilter.new(params)
    flash.now[:alert] = "Invalid date range, ignored." if @filter.invalid_range?
    @logs = @filter.apply(EventLog.all).sorted.paginate per_page: 30, page: params[:page]
  end

  def show
    @subscribers = @log.subscribers(current_user)
  end

  private

  def find_log
    @log = EventLog.find(params[:id])
  end

  def not_found_responder
    redirect_to("/admin/event_logs", alert: "Unknown event")
  end
end
