class Admin::ContainerImages::EnvParamsController < Admin::ContainerImages::BaseController

  before_action :find_env, only: [:edit, :update, :destroy]

  def new
    @env = @image.env_params.new
    render template: "container_images/env_params/new"
  end

  def edit
    render template: "container_images/env_params/edit"
  end

  def update
    if @env.update(env_params)
      redirect_to helpers.container_image_path(@image), success: "#{@env.name} updated."
    else
      render :edit
    end
  end

  def create
    @env = @image.env_params.new(env_params)
    @env.current_user = current_user
    if @env.save
      redirect_to helpers.container_image_path(@image), success: "#{@env.name} created."
    else
      render :new
    end
  end

  def destroy
    name = @env.name
    if @env.destroy
      flash[:success] = "#{name} deleted."
    else
      flash[:alert] = "Error: #{@env.errors.full_messages.join(' ')}"
    end
    redirect_to helpers.container_image_path(@image)
  end

  private

  def find_env
    @env = @image.env_params.find_by(id: params[:id])
    if @env.nil?
      redirect_to helpers.container_image_path(@image), alert: "Environmental variable not found."
      return false
    end
    @env.current_user = current_user
    @env.static_value = @env.value if @env.param_type == 'static'
    @env.env_value = @env.value if @env.param_type == 'variable'
  end

  def env_params
    params.require(:container_image_env_param).permit(:name, :label, :param_type, :static_value, :env_value)
  end


end