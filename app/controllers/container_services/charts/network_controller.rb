class ContainerServices::Charts::NetworkController < ContainerServices::BaseController

  def index
    data = [
      {
        name: 'transmit',
        data: []
      },
      {
        name: 'receive',
        data: []
      }
    ]
    if request.xhr?
      net = @service.metric_net_combined(3.hours.ago, Time.now)
      data = [
        {
          name: 'transmit',
          data: net[:tx]
        },
        {
          name: 'receive',
          data: net[:rx]
        }
      ]
    end
    respond_to do |format|
      format.html { }
      format.json { render json: data }
    end
  end

end
