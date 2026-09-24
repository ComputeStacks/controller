class Api::ContainerServices::MonarxController < Api::ContainerServices::BaseController
  ##
  # Generate an iframe url
  #
  # `POST /api/container_services/{container-service-id}/monarx`
  #
  # **OAuth AuthorizationRequire**: `project_write`
  #
  # * `monarx`: Object
  #     * `url`: String
  def create
    monarx_url = if @service.service_plugins.active.monarx.empty?
      ""
    else
      @service.service_plugins.active.monarx.first.monarx_plugin_url
    end

    data = {monarx: {url: monarx_url}}

    respond_to do |format|
      format.json { render json: data }
      format.xml { render xml: data }
    end
  end
end
