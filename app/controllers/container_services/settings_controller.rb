class ContainerServices::SettingsController < ContainerServices::BaseController

  before_action :find_setting, except: %i[index new create]

  def index; end

  def show
    if request.xhr?
      render plain: @setting.decrypted_value
    end
  end

  def new
    @setting = @service.setting_params.new param_type: 'static'
  end

  def create
    @setting = @service.setting_params.new new_setting_params
    @setting.param_type = 'static'
    if @setting.save
      redirect_to "/container_services/#{@service.id}/environmental", success: "Setting Added"
    else
      render action: :new
    end
  end

  def update
    if @setting.update(update_settings_params)
      redirect_to "/container_services/#{@service.id}/environmental", success: "Setting Updated"
    else
      render action: :edit
    end
  end

  def destroy
    @setting.safe_delete = true
    if @setting.destroy
      flash[:success] = "Setting Deleted"
    else
      flash[:alert] = "Error! #{@setting.errors.full_messages.join(' ')}"
    end
    redirect_to "/container_services/#{@service.id}/environmental"
  end

  private

  def find_setting
    @setting = @service.setting_params.find_by(id: params[:id])
    return(redirect_to("/container_services/#{@service.id}/environmental", alert: "Unknown setting")) if @setting.nil?
  end

  def new_setting_params
    params.require(:container_service_setting_config).permit(:name, :label, :value)
  end

  def update_settings_params
    params.require(:container_service_setting_config).permit(:label, :value)
  end

end
