class Admin::Volumes::LogsController < Admin::Volumes::BaseController

  def index
    if request.xhr?
      @logs = @volume.event_logs.where("created_at > ?", 1.week.ago).sorted.limit(5)
      render template: "admin/volumes/logs/list", layout: false
    else
      @logs = @volume.event_logs.sorted.paginate(per_page: 30, page: params[:page])
    end
  end

  def show
    @log = @volume.event_logs.find_by(id: params[:id])
    if @log.nil?
      redirect_to "/admin/volumes/#{@volume.id}/logs", alert: "Unknown log."
      return false
    end
    @subscribers = @log.subscribers(current_user)
  end

end
