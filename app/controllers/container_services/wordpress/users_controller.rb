class ContainerServices::Wordpress::UsersController < ContainerServices::Wordpress::BaseController

  def index
    if request.xhr?
      @users = ContainerServices::WordpressServices::UserService.new(@service).users
      render template: "container_services/wordpress/users/list", layout: false
    end
  end

end
