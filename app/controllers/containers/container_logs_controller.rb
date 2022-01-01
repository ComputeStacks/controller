class Containers::ContainerLogsController < Containers::BaseController

  def index
    if request.xhr?
      limit = params[:limit].to_i > 0 ? params[:limit] : 500
      @logs = @container.logs(1.day.ago, Time.now, limit)
      respond_to do |format|
        format.json { render json: @logs }
        format.xml { render xml: @logs }
        format.html { render template: "containers/container_logs/index", layout: false }
      end
    end
  end


end
