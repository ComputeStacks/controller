class Deployments::CertificatesController < Deployments::BaseController

  before_action :find_certificate, only: %w(show edit update destroy)

  def index
    @certs = @deployment.ssl_certificates
    @le_domains = @deployment.domains.where(le_enabled: true)
    if request.xhr?
      render template: "deployments/certificates/index", layout: false
    end
  end

  def show
    redirect_to "/deployments/#{@deployment.token}/certificates/#{@cert.id}/edit"
  end

  def new
    @cert = Deployment::Ssl.new
  end

  def edit; end

  def update
    if @cert.update(cert_params)
      redirect_to "/deployments/#{@cert.deployment.token}#ssl", notice: "Certificate updated"
    else
      render template: "deployments/certificates/edit"
    end
  end

  def create
    @cert = Deployment::Ssl.new(cert_params)
    @cert.current_user = current_user
    if @cert.save
      redirect_to "/deployments/#{@cert.deployment.token}", notice: "Certificate created"
    else
      render template: "deployments/certificates/new"
    end
  end

  def destroy
    if @cert.destroy
      if @cert.container_service&.load_balancer
        LoadBalancerServices::DeployConfigService.new(@cert.container_service.load_balancer).perform
      end
      flash[:notice] = "Certificate removed"
    else
      flash[:alert] = "Error: #{@cert.errors.full_messages.join(' ')}"
    end
    redirect_to "/deployments/#{@deployment.token}#ssl"
  end

  private

  def cert_params
    params.require(:deployment_ssl).permit(:container_service_id, :crt, :pkey, :ca)
  end

  def find_certificate
    @cert = @deployment.ssl_certificates.find_by(id: params[:id])
    return(redirect_to("/deployments/#{@deployment.token}#ssl", alert: "Unknown certificate")) if @cert.nil?
    @cert.current_user = current_user
  end


end
