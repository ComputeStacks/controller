class ContainerServices::IngressRules::BaseController < ContainerServices::BaseController

  include RescueResponder

  before_action :find_ingress_rule

  private

  def find_ingress_rule
    @ingress = @service.ingress_rules.find(params[:ingress_id])
    @ingress.current_user = current_user
  end

  def not_found_responder
    redirect_to helpers.container_service_path(@service)
  end

end
