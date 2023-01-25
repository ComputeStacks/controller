class ContainerServices::MonarxController < ContainerServices::BaseController

  def index
    @frame_link = if @service.service_plugins.active.monarx.empty?
                    nil
                  else
                    @service.service_plugins.active.monarx.first.monarx_plugin_url
                  end
    if @frame_link.nil?
      redirect_to "/container_services/#{@service.id}", alert: "Monarx not available."
    end
  end

end
