class Containers::Charts::DiskUsageController < Containers::BaseController

  def index
    respond_to do |format|
      format.html { }
      format.json { render json: @container.metric_disk_usage(3.hours.ago, Time.now) }
    end
  end

end
