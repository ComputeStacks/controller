class Admin::Deployments::Services::ServicePluginsController < Admin::Deployments::Services::BaseController

  before_action :find_plugin

  def edit; end

  def show
    redirect_to action: :edit
  end

  def update
    if @plugin.update plugin_params
      redirect_to base_url
    else
      render action: :edit
    end
  end

  def destroy
    if @plugin.destroy
      flash[:success] = "Service Addon deleted"
    else
      flash[:alert] = "Error deleting addon: #{@plugin.errors.full_messages.join(' ')}"
    end
    redirect_to base_url
  end

  private

  def plugin_params
    params.require(:deployment_container_service_service_plugin).permit(:active, :is_optional)
  end

  def find_plugin
    @plugin = @service.service_plugins.find params[:id]
    @plugin.current_audit = Audit.create_from_object!(@plugin, 'updated', request.remote_ip, current_user)
  end


end
