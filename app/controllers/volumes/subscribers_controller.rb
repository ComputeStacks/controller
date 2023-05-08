class Volumes::SubscribersController < Volumes::BaseController

  def index
    if request.xhr?
      @subscribers = @volume.attached_services
      render template: 'volumes/subscribers/list', layout: false
      return false
    end
  end

end
