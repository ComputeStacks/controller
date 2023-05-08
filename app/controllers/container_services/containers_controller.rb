class ContainerServices::ContainersController < ContainerServices::BaseController

  before_action :load_container, except: :index

  def index
    @containers = @service.containers.order(:name)
    respond_to do |format|
      format.html { render template: "containers/index", layout: !request.xhr? }
      format.json { render json: @containers }
      format.xml { render xml: @containers }
    end
  end

  private

  def load_container
     @container = @service.containers.find_by(id: params[:id])
     if @container.nil?
      if request.xhr?
        render plain: I18n.t('crud.unknown', resource: I18n.t('obj.container'))
      else
        redirect_to @service_base_url, alert: I18n.t('crud.unknown', resource: I18n.t('obj.container'))
      end
      return false
    end
  end

end
