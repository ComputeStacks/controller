class ContainerDomains::DnsCheckController < AuthController

  before_action :find_domain

  def create
    if @domain.le_ready
      flash[:notice] = "Domain already verified. Certificate will be generated shortly."
    else
      if LetsEncryptWorkers::ValidateDomainWorker.new.perform @domain.id
        flash[:notice] = "Domain verified. Certificate will be generated shortly."
      else
        flash[:alert] = "Error! Ensure #{@domain.domain} points to: #{@domain.expected_dns_entries.join(', ')}."
      end
    end
    redirect_to "/deployments/#{@deployment.token}"
  end

  private

  def find_domain
    @domain = Deployment::ContainerDomain.find_for current_user, { id: params[:container_domain_id] }
    return(redirect_to("/container_domains", alert: "Unknown domain")) if @domain.nil?
    @deployment = @domain.deployment
    @domain.current_user = current_user
    return(redirect_to("/container_domains/#{@domain.id}/edit", alert: "Error, domain does not belong to a service.")) if @deployment.nil?
  end

end
