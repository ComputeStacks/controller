class ContainerImages::IngressParamsController < ContainerImages::BaseController

  include RescueResponder

  before_action :find_ingress_rule, only: [:edit, :update, :destroy]

  def new
    @ingress = @image.ingress_params.new
  end

  def edit; end

  def update
    if @ingress.update(ingress_params)
      redirect_to helpers.container_image_path(@image), success: "#{@ingress.port} updated."
    else
      render :edit
    end
  end

  def create
    @ingress = @image.ingress_params.new(ingress_params)
    @ingress.current_user = current_user
    if @ingress.save
      redirect_to helpers.container_image_path(@image), success: "#{@ingress.port} created."
    else
      render :new
    end
  end

  def destroy
    name = @ingress.port
    if @ingress.destroy
      flash[:success] = "#{name} deleted."
    else
      flash[:alert] = "Error: #{@ingress.errors.full_messages.join(' ')}"
    end
    redirect_to helpers.container_image_path(@image)
  end

  private

  def find_ingress_rule
    @ingress = @image.ingress_params.find(params[:id])
    @ingress.current_user = current_user
  end

  def ingress_params
    params.require(:container_image_ingress_param).permit(:port, :proto, :backend_ssl, :external_access, :tcp_proxy_opt, :tcp_lb)
  end

  def not_found_responder
    redirect_to "/container_images/#{@image.id}", alert: "Ingress Rule Not Found"
  end


end
