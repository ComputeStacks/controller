class ContainerRegistry::CollaboratorsController < ContainerRegistry::BaseController

  before_action :check_permission
  before_action :find_collaborator, only: %i[destroy]

  def index
    @collaborators = @registry.container_registry_collaborators
    if request.xhr?
      render template: 'container_registry/collaborators/index', layout: false
    end
  end

  def new
    @collab = @registry.container_registry_collaborators.new
  end

  def create
    @collab = @registry.container_registry_collaborators.new user_email: collaborator_params[:user_email], current_user: current_user
    unless @collab.save
      flash[:alert] = @collab.errors.full_messages.join(' ')
    end
    redirect_to "/container_registry/#{@registry.id}/collaborators"
  end

  def destroy
    unless @collab.destroy
      flash[:alert] = "Error: #{@collab.errors.full_messages.join(' ')}"
    end
    redirect_to "/container_registry/#{@registry.id}/collaborators"
  end

  private

  def check_permission
    unless @registry.can_administer? current_user
      redirect_to "/container_registry/#{@registry.id}", alert: "Permission Denied"
    end
  end

  def find_collaborator
    @collab = @registry.container_registry_collaborators.find params[:id]
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:container_registry_collaborator).permit(:user_email)
  end

end
