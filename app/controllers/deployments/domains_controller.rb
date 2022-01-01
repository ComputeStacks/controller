class Deployments::DomainsController < Deployments::BaseController

  layout false

  def index
    @domains = @deployment.domains.where(system_domain: false).sorted
    if request.xhr?
      render template: 'deployments/domains/index', layout: false
    end
  end

end