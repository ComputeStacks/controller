class ContainerServices::Charts::MemoryController < ContainerServices::BaseController

  def index
    respond_to do |format|
      format.html { }
      format.json { render json: @service.metric_mem_usage(3.hours.ago, Time.now).map { |i| {name: i[0], data: i[1]}} }
    end
  end

  def throttled
    respond_to do |format|
      format.html { }
      format.json { render json: @service.metric_mem_throttled(3.hours.ago, Time.now).map { |i| {name: i[0], data: i[1]}} }
    end
  end

  def swap
    respond_to do |format|
      format.html { }
      format.json { render json: @service.metric_swap_usage(3.hours.ago, Time.now).map { |i| {name: i[0], data: i[1]}} }
    end
  end

end
