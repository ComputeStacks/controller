class Containers::Charts::NetworkController < Containers::BaseController
  def index
    net = @container.metric_net_combined(3.hours.ago, Time.now)
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
end
