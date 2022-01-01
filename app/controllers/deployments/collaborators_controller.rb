class Deployments::CollaboratorsController < Deployments::BaseController

  before_action :check_permission
  before_action :find_collaborator, only: %i[destroy]


  def index
    @collaborators = @deployment.deployment_collaborators.sorted
    if request.xhr?
      render template: 'deployments/collaborators/index', layout: false
    end
  end

  def new
    @collab = @deployment.deployment_collaborators.new
  end

  def create
    @collab = @deployment.deployment_collaborators.new user_email: collaborator_params[:user_email], current_user: current_user
    if @collab.save
      redirect_to "/deployments/#{@deployment.token}#collaborators"
    else
      render action: :new
    end
  end

  def destroy
    unless @collab.destroy
      flash[:alert] = "Error: #{@collab.errors.full_messages.join(' ')}"
    end
    redirect_to "/deployments/#{@deployment.token}#collaborators"
  end

  private

  def check_permission
    @deployment.can_administer? current_user
  end

  def find_collaborator
    @collab = @deployment.deployment_collaborators.find params[:id]
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:deployment_collaborator).permit(:user_email)
  end

end
