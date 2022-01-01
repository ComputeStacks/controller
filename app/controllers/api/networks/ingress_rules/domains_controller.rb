##
# List Domain Ingress Rules
class Api::Networks::IngressRules::DomainsController < Api::Networks::IngressRules::BaseController


  ##
  # List domains for this ingress rule
  #
  # `GET /api/networks/ingress_rules/{id}/domains`
  #
  # * `domains`: Array<Domain>
  #
  def index
    @domains = paginate @ingress_rule.container_domains
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/domains/index' }
    end
  end

end
