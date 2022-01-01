class Containers::Charts::CpuController < Containers::BaseController

  def index
    respond_to do |format|
      format.html { }
      format.json { render json: @container.metric_cpu_usage(3.hours.ago, Time.now) }
    end
  end

  def throttled
    respond_to do |format|
      format.html { }
      format.json { render json: @container.metric_cpu_throttled(3.hours.ago, Time.now) }
    end
  end

end
