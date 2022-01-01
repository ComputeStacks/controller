class Admin::SettingsController < Admin::ApplicationController

  before_action :load_setting, except: :index

  def index
    # little hack to force the 'general' settings to be first.
    @setting_groups = {'general' => Setting.general_settings.sorted}
    if Feature.check('demo')
      @setting_groups.merge! Setting.excluded_for_demo.sorted.group_by { |i| i.category }
    else
      @setting_groups.merge! Setting.display_list.sorted.group_by { |i| i.category }
    end
  end

  def edit
    if @setting.is_boolean?
      redirect_to "/admin/settings", alert: "Unable to edit boolean value"
    end
  end

  def update
    if @setting.is_boolean?
      if @setting.toggle_val!
        redirect_to "/admin/settings#s_#{@setting.category}", notice: "#{@setting.name} updated"
      else
        redirect_to "/admin/settings#s_#{@setting.category}", alert: "#{@setting.name} update failed"
      end
    else
      if @setting.update(setting_params)
        redirect_to "/admin/settings#s_#{@setting.category}", notice: "#{@setting.name} updated"
      else
        render template: 'admin/settings/edit'
      end
    end
  end

  private

  def setting_params
    params.require(:setting).permit(:value)
  end

  def load_setting
    if params[:id] == 'license'
      @setting = Setting.find_by(name: 'license_key')
    else
      @setting = Setting.where("name != 'license' and id = ?", params[:id]).first
    end
    if @setting.nil?
      redirect_to "/admin/settings", alert: "Unknown Setting."
      return false
    end
    @setting.current_user = current_user
  end

end
