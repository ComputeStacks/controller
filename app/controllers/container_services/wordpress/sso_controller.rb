class ContainerServices::Wordpress::SsoController < ContainerServices::Wordpress::BaseController

  def create
    u = params[:user].blank? ? 'admin' : params[:user]
    s = ContainerServices::WordpressServices::SsoService.new(@service, u)
    if s.perform
      redirect_to s.link, allow_other_host: true
    else
      redirect_to "/container_services/#{@service.id}", alert: "Error generating sso link"
    end
  end

end
