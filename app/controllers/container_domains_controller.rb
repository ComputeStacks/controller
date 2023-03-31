class ContainerDomainsController < AuthController

  before_action :find_domain, only: %w(show edit update destroy)
  before_action :load_project_services, only: %w(new edit update create)

  def index
    @domains = Deployment::ContainerDomain.find_all_for(current_user).where(system_domain: false)
  end

  def show
    redirect_to "/container_domains/#{@domain.id}-#{@domain.domain.parameterize}/edit"
  end

  def new
    @domain = current_user.container_domains.new
    @domain.le_enabled = true
    @domain.container_service = @service if @service
  end

  def edit; end

  def update
    if @domain.update(domain_params)
      redirect_to @deployment.nil? ? "/container_domains" : "/deployments/#{@deployment.token}#domains", notice: "Domain updated."
    else
      render template: "container_domains/edit"
    end
  end

  def create
    if @deployment.nil?
      redirect_to "/container_domains/new", alert: "Missing project"
      return false
    end
    @domain = @deployment.user.container_domains.new(domain_params)
    @domain.user = @deployment.user
    @domain.current_user = current_user
    if @domain.save
      @deployment = @domain.deployment
      redirect_to @deployment.nil? ? "/container_domains" : "/deployments/#{@deployment.token}#domains", notice: "Domain created."
    else
      render template: "container_domains/new"
    end
  end

  def destroy
    if @domain.destroy
      flash[:notice] = "Domain deleted"
    else
      flash[:alert] = "Error removing domain: #{@domain.errors.full_messages.join(' ')}"
    end
    redirect_to @deployment.nil? ? "/container_domains" : "/deployments/#{@deployment.token}#domains"
  end

  private

  def domain_params
    params.require(:deployment_container_domain).permit(:domain, :le_enabled, :enabled, :ingress_rule_id, :header_hsts, :force_https)
  end

  def find_domain
    @domain = Deployment::ContainerDomain.find_for current_user, { id: params[:id] }
    return(redirect_to("/container_domains", alert: "Unknown domain")) if @domain.nil?
    @deployment = @domain.deployment
    @domain.current_user = current_user
    @domain.header_hsts = true if @domain.enable_hsts_header?
  end

  def load_project_services
    if @domain && @domain.ingress_rule&.container_service
      @service = @domain.ingress_rule.container_service
      @deployment = @service.deployment
    elsif params[:service_id]
      @service = Deployment::ContainerService.find_for(current_user, id: params[:service_id])
      @deployment = @service.deployment if @service
    end
    @deployment = Deployment.find_for(current_user, token: params[:deployment_id]) if params[:deployment_id]
    @deployment = @image.deployment if @image&.deployment
    @services = if @deployment.nil?
                  Deployment::ContainerService.find_all_for(current_user).web_only
                else
                  @deployment.services.web_only.sorted
                end
    @ingress_rules = if @service
      @service.ingress_rules.where(external_access: true)
    else
      []
    end
  end

end
