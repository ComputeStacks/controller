class ContainerServices::ServicePluginsController < ContainerServices::BaseController

  def index
    @available_plugins = @service.service_plugins.optional
  end

  def create
    plugin_list = addon_params.empty? ? [] : addon_params['new_plugin_list'].map { |i| i.to_i }
    @service.current_audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
    if @service.update(new_plugin_list: plugin_list)
      redirect_to "/container_services/#{@service.id}", success: "Addons updated successfully. Please rebuild your containers to apply changes."
    else
      render template: 'index'
    end
  end

  private

  def addon_params
    params.permit(new_plugin_list: [])
  end

end
