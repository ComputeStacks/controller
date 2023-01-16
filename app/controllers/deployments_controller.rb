class DeploymentsController < AuthController

  before_action :find_deployment, only: [:show, :update, :destroy]
  before_action :require_administer, only: :destroy

  def index
    @deployments = Deployment.find_all_for(current_user).sort_by_name
    @pending_orders = current_user.orders.pending_projects
    if request.xhr?
      render template: "deployments/index/deployment_list", layout: false
    end
  end

  def show; end

  def update
    @deployment.name = params[:name]
    if @deployment.save
      flash[:notice] = I18n.t('crud.updated', resource: I18n.t('obj.deployment'))
    else
      flash[:alert] = I18n.t('common.general_error')
    end
    redirect_to "/deployments/#{@deployment.token}"
  end

  def destroy
    audit = Audit.create_from_object!(@deployment, 'deleted', request.remote_ip, current_user)
    event = EventLog.create!(
      locale: 'deployment.trash',
      locale_keys: { project: @deployment.name },
      event_code: '20cd984da4da8963',
      audit: audit,
      status: 'pending'
    )
    @deployment.mark_trashed!
    event.deployments << @deployment
    ProjectWorkers::TrashProjectWorker.perform_async @deployment.global_id, event.global_id
    redirect_to '/deployments', notice: 'Project queued for deletion'
  end

  private

  def find_deployment
    @deployment = Deployment.find_for current_user, { token: params[:id] }
    if @deployment.nil?
      if params[:js] || request.xhr?
        render plain: I18n.t('crud.unknown', resource: I18n.t('obj.deployment')), layout: false
      else
        redirect_to "/deployments", alert: I18n.t('crud.unknown', resource: I18n.t('obj.deployment'))
      end
      return false
    end
    @deployment.current_user = current_user
  end

  def project_params
    params.require(:deployment).permit(:name, :tag_list)
  end

  def require_administer
    unless @deployment.can_administer? current_user
      redirect_to "/deployments/#{@deployment.token}", alert: "Permission denied"
    end
  end

end
