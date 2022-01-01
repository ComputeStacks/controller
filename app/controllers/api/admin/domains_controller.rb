##
# # Domains Controller
class Api::Admin::DomainsController < Api::Admin::ApplicationController

  ##
  # List all ingress rules
  #
  # `GET /api/admin/domains`
  #
  # Schema is same as end-user api.
  #
  def index
    @domains = paginate Deployment::ContainerDomain.all.order(:id)
  end

end
