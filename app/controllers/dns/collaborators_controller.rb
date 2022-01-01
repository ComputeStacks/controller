class Dns::CollaboratorsController < Dns::BaseController

  before_action :check_permission
  before_action :find_collaborator, only: %i[destroy]

  def index
    @collaborators = @zone.dns_zone_collaborators
    if request.xhr?
      render template: 'dns/collaborators/index', layout: false
    end
  end

  def new
    @collab = @zone.dns_zone_collaborators.new
  end

  def create
    @collab = @zone.dns_zone_collaborators.new user_email: collaborator_params[:user_email], current_user: current_user
    unless @collab.save
      flash[:alert] = @collab.errors.full_messages.join(' ')
    end
    redirect_to "/dns/#{@zone.id}/collaborators"
  end

  def destroy
    unless @collab.destroy
      flash[:alert] = "Error: #{@collab.errors.full_messages.join(' ')}"
    end
    redirect_to "/dns/#{@zone.id}/collaborators"
  end

  private

  def check_permission
    unless @zone.can_administer? current_user
      redirect_to "/dns/#{@zone.id}", alert: "Permission Denied"
    end
  end

  def find_collaborator
    @collab = @zone.dns_zone_collaborators.find_by id: params[:id]
    return redirect_to("/dns/#{@zone.id}", alert: "Unknown Collaborator") if @collab.nil?
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:dns_zone_collaborator).permit(:user_email)
  end

end
