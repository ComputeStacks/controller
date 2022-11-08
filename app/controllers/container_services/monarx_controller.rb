class ContainerServices::MonarxController < ContainerServices::BaseController

  before_action :ensure_monarx_available

  def index

    @frame_link = @service.monarx_plugin_url
    if @frame_link.nil?
      redirect_to "/container_services/#{@service.id}", alert: "Monarx not available."
      return false
    end

  end


  private

  def ensure_monarx_available
    unless @service.monarx_available?
      redirect_to "/container_services/#{@service.id}", alert: "Monarx not available."
      return false
    end
  end

end
