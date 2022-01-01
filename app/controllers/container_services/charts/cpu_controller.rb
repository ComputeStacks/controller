class ContainerServices::Charts::CpuController < ContainerServices::BaseController

  def index
    respond_to do |format|
      format.html { }
      format.json { render json: @service.metric_cpu_usage(3.hours.ago, Time.now).map { |i| {name: i[0], data: i[1]}} }
    end
  end

  def throttled
    respond_to do |format|
      format.html { }
      format.json { render json: @service.metric_cpu_throttled(3.hours.ago, Time.now).map { |i| {name: i[0], data: i[1]}} }
    end
  end

end
