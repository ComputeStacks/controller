##
# Container Service Ingress Rules
class Api::ContainerServices::IngressRulesController < Api::ContainerServices::BaseController

  ##
  # List Ingress Rules
  #
  # `GET /api/container_services/{container-service-id}/ingress_rules`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `ingress_rules`: Array<IngressRule>
  #
  def index
    @ingress_rules = @service.ingress_rules
  end

end
