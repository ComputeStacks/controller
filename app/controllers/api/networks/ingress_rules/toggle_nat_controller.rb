##
# Ingress Rule Toggle NAT API
#
# This is a helper method to toggle external access to an ingress rule.
# You may also edit the ingress rule and specify `external_access`.
#
class Api::Networks::IngressRules::ToggleNatController < Api::Networks::IngressRules::BaseController

  ##
  # Toggle External Access
  #
  # `POST /api/networks/ingress_rules/{id}/toggle_nat`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  def create
    if @ingress_rule.toggle_nat!
      respond_to do |format|
        format.any(:json, :xml) { render template: 'api/networks/ingress_rules/show', status: :accepted }
      end
    else
      respond_to do |format|
        format.any(:json, :xml) { head :unprocessable_entity }
      end
    end
  end

end
