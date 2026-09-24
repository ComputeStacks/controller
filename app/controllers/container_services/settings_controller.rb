class ContainerServices::SettingsController < ContainerServices::BaseController
  before_action :find_setting, except: %i[index new create]

  def index
  end

  def show
    if request.xhr?
      render plain: @setting.decrypted_value
    end
  end

  def new
    @setting = @service.setting_params.new param_type: "static"
  end

  def create
    @setting = @service.setting_params.new new_setting_params
    @setting.param_type = "static" if @setting.param_type.blank?
    if @setting.param_type == "password"
      if @setting.value.blank?
        @setting.errors.add(:value, "can't be blank")
        return render(action: :new)
      end
      # Encryption happens here, not in a model hook: `gen_settings_config!` already
      # hands the model ciphertext, so a `before_save` would double-encrypt it.
      @setting.value = Secret.encrypt!(@setting.value)
    end
    if @setting.save
      redirect_to "/container_services/#{@service.id}/environmental", success: "Setting Added"
    else
      # Never echo ciphertext back into the form -- resubmitting it would encrypt twice.
      @setting.value = nil if @setting.param_type == "password"
      render action: :new
    end
  end

  def update
    attrs = update_settings_params.to_h
    if @setting.param_type == "password"
      # There is no way to render the current password into the form, so a blank
      # submission can only mean "leave it alone". Static settings are the opposite:
      # blanking one is how an operator disables it, so blank is assigned verbatim.
      if attrs["value"].blank?
        attrs.delete("value")
      else
        attrs["value"] = Secret.encrypt!(attrs["value"])
      end
    end
    if @setting.update(attrs)
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
      flash[:alert] = "Error! #{@setting.errors.full_messages.join(" ")}"
    end
    redirect_to "/container_services/#{@service.id}/environmental"
  end

  private

  def find_setting
    @setting = @service.setting_params.find_by(id: params[:id])
    redirect_to("/container_services/#{@service.id}/environmental", alert: "Unknown setting") if @setting.nil?
  end

  def new_setting_params
    params.require(:container_service_setting_config).permit(:name, :label, :value, :param_type)
  end

  def update_settings_params
    params.require(:container_service_setting_config).permit(:label, :value)
  end
end
