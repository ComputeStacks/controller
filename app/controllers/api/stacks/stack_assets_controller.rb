# @deprecated
class Api::Stacks::StackAssetsController < Api::Stacks::BaseController

  # before_action :load_remote_resource

  # GET /stacks/assets/:id
  #
  def show
    if @deployment && params[:id]
      case params[:id]
      when "pma"
        @mysql_servers = []
        @deployment.deployed_containers.each do |i|
          if params[:h]
            @container = @deployment.deployed_containers.find_by(name: params[:h])
          else
            @container = nil
          end
          @mysql_servers << i if i.container_image.role == 'mysql'
        end
      else
        render json: {'success' => false, 'message' => "unknown resource for project"}, status: :not_found
        return false
      end
      begin
        stream = render_to_string(:template => "api/stacks/#{params[:id]}")
        send_data(stream, :type => "text/plain", :filename => params[:id])
      rescue
       render :json => {'success' => false}, :status => 200
      end
    else
      render json: {'success' => false, 'message' => 'unknown resource'}, status: :not_found
    end
  end

end
