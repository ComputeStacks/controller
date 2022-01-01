class Admin::EventLogsController < Admin::ApplicationController

  include RescueResponder

  before_action :find_log, only: :show

  def index
    logs = case params[:status]
           when 'failed'
             EventLog.failed
           when 'active'
             EventLog.active
           when 'running'
             EventLog.where(status: 'running')
           when 'pending'
             EventLog.where(status: 'pending')
           when 'completed'
             EventLog.where(status: 'completed')
           when 'cancelled'
             EventLog.where(status: 'cancelled')
           else
             EventLog
           end
    @logs = logs.sorted.paginate per_page: 30, page: params[:page]
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
