class Admin::Deployments::Domains::VerifyDnsController < Admin::Deployments::BaseController

  before_action :load_domain

  def create
    unless @domain.le_ready

      unless LetsEncryptWorkers::ValidateDomainWorker.new.perform @domain.id
        flash[:alert] = "Error! Ensure #{@domain.domain} points to: #{@domain.expected_dns_entries.join(', ')}."
      end
    end
    redirect_to "/admin/deployments/#{@deployment.id}"
  end

  private

  def load_domain
    @domain = @deployment.domains.find_by(id: params[:domain_id])
    return(redirect_to("/admin/deployments/#{@deployment.id}", alert: "Unknown Domain")) if @domain.nil?
  end

end
