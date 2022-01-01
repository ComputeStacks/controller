class Admin::Dns::CollaboratorsController < Admin::Dns::BaseController

  before_action :check_permission
  before_action :find_collaborator, only: %i[destroy]

  def index
    @collaborators = @zone.dns_zone_collaborators
    if request.xhr?
      render template: 'admin/dns/collaborators/index', layout: false
    end
  end

  def new
    @collab = @zone.dns_zone_collaborators.new
  end

  def create
    @collab = @zone.dns_zone_collaborators.new collaborator_params
    @collab.current_user = current_user
    unless @collab.save
      flash[:alert] = @collab.errors.full_messages.join(' ')
    end
    redirect_to "/admin/dns/#{@zone.id}/collaborators"
  end

  def destroy
    unless @collab.destroy
      flash[:alert] = "Error: #{@collab.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/dns/#{@zone.id}/collaborators"
  end

  private

  def check_permission
    @zone.can_administer? current_user
  end

  def find_collaborator
    @collab = @zone.dns_zone_collaborators.find params[:id]
    @collab.current_user = current_user
  end

  def collaborator_params
    params.require(:dns_zone_collaborator).permit(:user_email, :skip_confirmation)
  end

end
