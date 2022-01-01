class ContainerImages::SettingParamsController < ContainerImages::BaseController

  before_action :find_setting, only: [:edit, :update, :destroy]

  def new
    @setting = @image.setting_params.new
  end

  def edit; end

  def update
    if @setting.update(setting_params)
      redirect_to helpers.container_image_path(@image), success: "#{@setting.name} updated."
    else
      render :edit
    end
  end

  def create
    @setting = @image.setting_params.new(setting_params)
    @setting.current_user = current_user
    if @setting.save
      redirect_to helpers.container_image_path(@image), success: "#{@setting.name} created."
    else
      render :new
    end
  end

  def destroy
    name = @setting.name
    if @setting.destroy
      flash[:success] = "#{name} deleted."
    else
      flash[:alert] = "Error: #{@setting.errors.full_messages.join(' ')}"
    end
    redirect_to helpers.container_image_path(@image)
  end

  private

  def find_setting
    @setting = @image.setting_params.find_by(id: params[:id])
    if @setting.nil?
      redirect_to helpers.container_image_path(@image), alert: "Setting not found."
      return false
    end
    @setting.current_user = current_user
  end

  def setting_params
    params.require(:container_image_setting_param).permit(:name, :label, :param_type, :value)
  end


end