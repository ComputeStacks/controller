class Admin::Volumes::SubscribersController < Admin::Volumes::BaseController

  def index
    if request.xhr?
      @subscribers = @volume.attached_services
      render template: 'admin/volumes/subscribers/list', layout: false
    end
  end

end
