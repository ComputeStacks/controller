class CollaborationsController < AuthController

  before_action :find_collab, except: :index

  def index
    @projects = DeploymentCollaborator.find_all_for_user current_user
    @registries = ContainerRegistryCollaborator.find_all_for_user current_user
    @domains = Dns::ZoneCollaborator.find_all_for_user current_user
    @images = ContainerImageCollaborator.find_all_for_user current_user
  end

  # Accept Invitation
  def update
    if @collab.active || @collab.update(active: true)
      flash[:notice] = I18n.t('collaborators.events.accept_invite')
    else
      flash[:alert] = @collab.errors.full_messages.join(' ')
    end
    redirect_to "/collaborations"
  end

  # Revoke or Deny invite
  def destroy
    if @collab.destroy
      flash[:notice] = I18n.t('collaborators.events.remove_invite')
    else
      flash[:alert] = @collab.errors.full_messages.join(' ')
    end
    redirect_to "/collaborations"
  end

  private

  def find_collab
    # params[:id] = ID-model
    id = params[:id].split('-')[0].to_i
    collab_model = params[:id].split('-')[1]
    allowed_models = %w(project image registry zone)
    @collab = if allowed_models.include?(collab_model) && id > 0
                 case collab_model
                 when 'project'
                   DeploymentCollaborator.find_for_user current_user, id: id
                 when 'image'
                   ContainerImageCollaborator.find_for_user current_user, id: id
                 when 'registry'
                   ContainerRegistryCollaborator.find_for_user current_user, id: id
                 when 'zone'
                   Dns::ZoneCollaborator.find_for_user current_user, id: id
                 else
                   nil
                 end
               else
                 nil
              end
    return redirect_to("/collaborations", alert: "Not found") if @collab.nil?
    @collab.current_user = current_user
  end

end
