class ContainerServices::EnvironmentalController < ContainerServices::BaseController

  before_action :find_env, only: [:edit, :update, :destroy]

  def index; end

  def show
    redirect_to action: :edit
  end

  def new
    @env = @service.env_params.new
  end

  def create
    @env = @service.env_params.new(service_env_params)
    if @env.save
      redirect_to "/container_services/#{@service.id}/environmental", success: "#{@env.name} created successfully."
    else
      render action: :new
    end
  end

  def edit; end

  def update
    if @env.update(service_env_params)
      redirect_to "/container_services/#{@service.id}/environmental", success: "#{@env.name} updated successfully."
    else
      render action: :edit
    end
  end

  def destroy
    name = @env.name
    if @env.destroy
      redirect_to "/container_services/#{@service.id}/environmental", success: "#{name} deleted successfully."
    else
      redirect_to "/container_services/#{@service.id}/environmental", alert: "Error! #{@env.errors.full_messages.join(' ')}"
    end
  end

  private

  def find_env
    @env = @service.env_params.find_by(id: params[:id])
    if @env.nil?
      return redirect_to action: :index, alert: "Unknown environmental parameter"
    end
    @env.current_user = current_user
    @env.static_value = @env.value if @env.param_type == 'static'
  end

  def service_env_params
    params.require(:container_service_env_config).permit(:name, :label, :param_type, :env_value, :static_value)
  end

end
