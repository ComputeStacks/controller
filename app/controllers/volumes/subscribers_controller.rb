class Volumes::SubscribersController < Volumes::BaseController

  def index
    if params[:js]
      @subscribers = @volume.attached_services
      render template: 'volumes/subscribers/list', layout: false
      return false
    end
  end

end