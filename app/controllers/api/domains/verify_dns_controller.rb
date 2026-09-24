##
# Validate Domain
#
# Manually verify a domain to enable LetsEncrypt. This will happen automatically every 10-15minutes.
#
class Api::Domains::VerifyDnsController < Api::ApplicationController
  api_scope create: :project_write

  before_action :load_domain

  ##
  # Verify Domain
  #
  # `POST /api/domains/{id}/verify_dns`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  def create
    unless @domain.le_ready
      unless LetsEncryptWorkers::ValidateDomainWorker.new.perform @domain.id
        return api_obj_error("Error! Ensure #{@domain.domain} points to: #{@domain.expected_dns_entries.join(", ")}.")
      end
    end
    respond_to do |format|
      format.json { render json: {}, status: :accepted }
      format.xml { render xml: {}, status: :accepted }
    end
  end

  private

  def load_domain
    @domain = Deployment::ContainerDomain.find_for(current_user, id: params[:id])
    api_obj_missing("Unknown Domain") if @domain.nil?
  end
end
