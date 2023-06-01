class Admin::ContainerDomainsController < Admin::ApplicationController

  before_action :find_domain, only: %w(show edit update destroy)
  before_action :load_project_services, only: %w(new edit update create)

  def index
    domains = Deployment::ContainerDomain
    domains = case params[:status]
              when 'disabled'
                domains.where(enabled: false)
              else
                domains.where(enabled: true)
              end
    domains = case params[:kind]
              when 'system'
                domains.where(system_domain: true)
              else
                domains.where(system_domain: false)
              end
    domains = case params[:le]
              when 'active'
                domains.where(le_enabled: true, le_ready: true)
              when 'pending'
                domains.where(le_enabled: true, le_ready: false)
              else
                domains
              end
    domains = case params[:service]
              when 'linked'
                domains.where.not(ingress_rule: nil)
              when 'unlinked'
                domains.where(ingress_rule: nil)
              else
                domains
              end
    @domains = domains.sorted.paginate per_page: 30, page: params[:page]
  end

  def new
    @domain = Deployment::ContainerDomain.new
    @services = []
  end

  def edit; end

  def update
    if @domain.update((@domain.system_domain ? system_domain_params : domain_params))
      redirect_to @base_url, success: "Domain updated."
    else
      render template: "admin/container_domains/edit"
    end
  end

  def create
    @domain = Deployment::ContainerDomain.new(domain_params)
    @domain.current_user = current_user
    if @domain.save
      if @domain.container_service.nil?
        redirect_to "/admin/container_domains/#{@domain.id}", notice: "Domain created successfully. Not active until linked to a service."
      else
        if @domain.deployment
          @deployment = @domain.deployment
          redirect_to "/admin/deployments/#{@deployment.id}#domains", success: "Domain created."
        else
          redirect_to "/admin/container_domains", success: "Domain created."
        end
      end
    else
      if @domain.user
        @services = @domain.user.container_services.sorted
      else
        @services = []
      end
      render template: "admin/container_domains/new"
    end
  end

  def destroy
    return(redirect_to(@base_url, alert: "Unable to remove system domains")) if @domain.system_domain
    if @domain.destroy
      redirect_to @base_url, notice: "Domain deleted."
    else
      redirect_to @base_url, alert: "Unable to delete domain: #{@domain.errors.full_messages.join(' ')}"
    end
  end

  private

  def find_domain
    @domain = Deployment::ContainerDomain.find_by(id: params[:id])
    if @domain&.deployment
      @deployment = @domain.deployment
      @base_url = "/admin/deployments/#{@deployment.id}#domains"
    else
      @base_url = "/admin/container_domains"
    end
    return redirect_to(@base_url, alert: "Unknown domain") if @domain.nil?
    @domain.current_user = current_user
    @services = @domain.user.container_services.sorted
  end

  def domain_params
    params.require(:deployment_container_domain).permit(:domain, :le_enabled, :enabled, :ingress_rule_id, :user_id, :header_hsts, :force_https)
  end

  def system_domain_params
    params.require(:deployment_container_domain).permit(:enabled)
  end

  def load_project_services
    if @domain && @domain.ingress_rule&.container_service
      @service = @domain.ingress_rule.container_service
      @deployment = @service.deployment
    elsif params[:service_id]
      @service = Deployment::ContainerService.find_by(id: params[:service_id])
      @deployment = @service.deployment if @service
    end
    @deployment = Deployment.find_by(token: params[:deployment_id]) if params[:deployment_id]
    @deployment = @image.deployment if @image&.deployment
    @services = if @deployment.nil?
      Deployment::ContainerService.web_only.sorted
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
