class ContainerRegistry::BaseController < AuthController

  before_action :find_registry

  private

  def find_registry
    @registry = ContainerRegistry.find_for current_user, { id: params[:container_registry_id] }
    if @registry.nil?
      respond_to do |format|
        format.json { render json: [].to_json }
        format.xml { render xml: [].to_xml }
        format.html { redirect_to("/container_registry") }
      end
      return false
    end
    @registry.current_user = current_user
  end

end
