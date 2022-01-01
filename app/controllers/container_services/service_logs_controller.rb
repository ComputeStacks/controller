class ContainerServices::ServiceLogsController < ContainerServices::BaseController

  def index
    if request.xhr?
      @logs = @service.logs(3.days.ago, Time.now)
      respond_to do |format|
        format.json { render json: @logs }
        format.xml { render xml: @logs }
        format.html { render layout: false }
      end
    end
  end

end
