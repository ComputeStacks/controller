class Admin::Users::ContainerServicesController < Admin::Users::ApplicationController

  def index
    if request.xhr?
      @services = @user.container_services.sorted
      respond_to do |format|
        format.json { render json: @services }
        format.xml { render xml: @services }
      end
    else
      @services = @user.container_services.sorted.paginate per_page: 30, page: params[:page]
    end

  end

end