class ContainerRegistry::RegistryConnectController < ContainerRegistry::BaseController

  def index; end

  def show
    if request.xhr?
      render plain: @registry.registry_password, layout: false
    else
      redirect_to action: :index
    end
  end

end
