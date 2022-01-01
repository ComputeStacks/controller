class ContainerServices::IngressRules::ToggleNatController < ContainerServices::IngressRules::BaseController

  def create
    if @ingress.toggle_nat!
      flash[:success] = "Service update queued."
    else
      flash[:alert] = @service.errors.full_messages.join(' ')
    end
    redirect_to helpers.container_service_path(@service)
  end

end
