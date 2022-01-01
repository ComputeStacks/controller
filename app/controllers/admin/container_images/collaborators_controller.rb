class Admin::ContainerImages::CollaboratorsController < Admin::ContainerImages::BaseController

  before_action :find_collaborator, only: %i[destroy]

  def index
    @collaborators = @image.container_image_collaborators.sorted
    if request.xhr?
      render template: 'admin/container_images/collaborators/index', layout: false
    end
  end

  def new
    @collab = @image.container_image_collaborators.new
  end

  def create
    @collab = @image.container_image_collaborators.new collaborator_params
    @collab.current_user = current_user
    unless @collab.save
      flash[:alert] = @collab.errors.full_messages.join(' ')
    end
    redirect_to "/admin/container_images/#{@image.id}/collaborators"
  end

  def destroy
    unless @collab.destroy
      flash[:alert] = "Error: #{@collab.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/container_images/#{@image.id}/collaborators"
  end

  private

  def find_collaborator
    @collab = @image.container_image_collaborators.find params[:id]
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:container_image_collaborator).permit(:user_email, :skip_confirmation)
  end

end
