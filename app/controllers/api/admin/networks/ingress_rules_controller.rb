##
# # Network Ingress Rules
class Api::Admin::Networks::IngressRulesController < Api::Admin::ApplicationController

  ##
  # List all ingress rules
  #
  # `GET /api/admin/networks/ingress_rules`
  #
  # Schema is same as end-user api.
  #
  def index
    @ingress_rules = paginate Network::IngressRule.all.order(:id)
  end

end
