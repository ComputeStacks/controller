class ContainerServices::Wordpress::BaseController < ContainerServices::BaseController

  before_action :valid_role?

  private

  def valid_role?
    unless @service.is_wordpress?
      if request.xhr?
        render plain: ""
      else
        redirect_to "/deployments", notice: "Invalid image type"
      end
      return false
    end
  end

end
