# @deprecated Will replace with MetaData service
class Api::Cluster::AssetsController < Api::Cluster::BaseController

  def index
    if @service.container_image.role == "pma"
      render json: ['pma']
    else
      render json: []
    end
  end

  def show
    case params[:id]
    when 'pma'
      if @service.container_image.role == 'pma'
        @mysql_servers = []
        @project.deployed_containers.each do |i|
          @mysql_servers << i if i.container_image.role == 'mysql'
        end
        stream = render_to_string(template: "api/cluster/assets/pma")
        send_data(stream, type: "text/plain", filename: "config.inc.php")
      else
        head :not_found
      end
    else
      head :not_found
    end
  end

end
