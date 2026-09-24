class ContainerServices::Charts::LoadBalancerController < ContainerServices::BaseController
  def index
    net = @service.metric_lb_combined(3.hours.ago, Time.now)
    data = [
      {
        name: "transmit",
        data: net[:tx]
      },
      {
        name: "receive",
        data: net[:rx]
      }
    ]
    respond_to do |format|
      format.html {}
      format.json { render json: data }
    end
  end

  def sessions
    respond_to do |format|
      format.html {}
      format.json { render json: @service.metric_lb_sessions(3.hours.ago, Time.now) }
    end
  end
end
