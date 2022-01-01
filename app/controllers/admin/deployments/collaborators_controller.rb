class Admin::Deployments::CollaboratorsController < Admin::Deployments::BaseController

  before_action :find_collaborator, only: %i[destroy]

  def index
    @collaborators = @deployment.deployment_collaborators.sorted
    if request.xhr?
      render template: 'admin/deployments/collaborators/index', layout: false
    end
  end

  def new
    @collab = @deployment.deployment_collaborators.new
  end

  def create
    @collab = @deployment.deployment_collaborators.new collaborator_params
    @collab.current_user = current_user
    # render plain: ActiveRecord::Type::Boolean.new.cast(@collab.skip_confirmation)
    # return false
    if @collab.save
      redirect_to "/admin/deployments/#{@deployment.id}#collaborators"
    else
      render action: :new
    end
  end

  def destroy
    unless @collab.destroy
      flash[:alert] = "Error: #{@collab.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/deployments/#{@deployment.id}#collaborators"
  end

  private

  def find_collaborator
    @collab = @deployment.deployment_collaborators.find params[:id]
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:deployment_collaborator).permit(:user_email, :skip_confirmation)
  end

end
