class ContainerServices::IngressController < ContainerServices::BaseController

  include RescueResponder

  before_action :find_ingress_rule, except: %i[index new create]

  def index
    @ingress_rules = @service.ingress_rules
    if request.xhr?
      respond_to do |format|
        format.html { render layout: false }
        format.json { render json: @ingress_rules }
        format.xml { render xml: @ingress_rules }
      end
    end
  end

  def new
    @ingress = @service.ingress_rules.new
  end

  def edit; end

  def create
    params[:network_ingress_rule][:tcp_lb] = false if @service.public_network?
    @ingress = @service.ingress_rules.new(ingress_params)
    @ingress.region = @service.region
    if @ingress.save
      flash[:success] = "updated"
      if params[:return_to] == 'service'
        redirect_to helpers.container_service_path(@service)
      else
        redirect_to "/container_services/#{@service.id}/ingress"
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    params[:network_ingress_rule][:tcp_lb] = false if @service.public_network?
    if @ingress.update(ingress_params)
      flash[:success] = "updated"
      if params[:return_to] == 'service'
        redirect_to helpers.container_service_path(@service)
      else
        redirect_to "/container_services/#{@service.id}/ingress"
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @ingress.destroy
      flash[:success] = "Rule deleted"
    else
      flash[:alert] = "Error! #{@ingress.errors.full_messages.join(' ')}"
    end
    redirect_to "/container_services/#{@service.id}/ingress"
  end

  private

  def find_ingress_rule
    @ingress = @service.ingress_rules.find(params[:id])
    @ingress.current_user = current_user
  end

  def ingress_params
    params.require(:network_ingress_rule).permit(:proto, :port, :external_access, :tcp_proxy_opt, :backend_ssl, :restrict_cf, :tcp_lb)
  end

  def not_found_responder
    redirect_to helpers.container_service_path(@service)
  end

end
