class Admin::ContainerRegistry::CollaboratorsController < Admin::ContainerRegistry::BaseController

  before_action :find_collaborator, only: %i[destroy]

  def index
    @collaborators = @registry.container_registry_collaborators
    if request.xhr?
      render template: 'admin/container_registry/collaborators/index', layout: false
    end
  end

  def new
    @collab = @registry.container_registry_collaborators.new
  end

  def create
    @collab = @registry.container_registry_collaborators.new collaborator_params
    @collab.current_user = current_user
    unless @collab.save
      flash[:alert] = @collab.errors.full_messages.join(' ')
    end
    redirect_to "/admin/container_registry/#{@registry.id}/collaborators"
  end

  def destroy
    unless @collab.destroy
      flash[:alert] = "Error: #{@collab.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/container_registry/#{@registry.id}/collaborators"
  end

  private

  def find_collaborator
    @collab = @registry.container_registry_collaborators.find params[:id]
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:container_registry_collaborator).permit(:user_email, :skip_confirmation)
  end

end
