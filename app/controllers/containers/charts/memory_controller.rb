class Containers::Charts::MemoryController < Containers::BaseController

  def index
    respond_to do |format|
      format.html { }
      format.json { render json: @container.metric_mem_usage(3.hours.ago, Time.now) }
    end
  end

  def throttled
    respond_to do |format|
      format.html { }
      format.json { render json: @container.metric_mem_throttled(3.hours.ago, Time.now) }
    end
  end

  def swap
    respond_to do |format|
      format.html { }
      format.json { render json: @container.metric_swap_usage(3.hours.ago, Time.now) }
    end
  end

end
