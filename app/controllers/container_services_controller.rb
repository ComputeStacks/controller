class ContainerServicesController < AuthController

  include RescueResponder

  before_action :find_service, except: [:index, :new]

  def index
    @services = Deployment::ContainerService.find_all_for(current_user).paginate page: params[:page], per_page: 25
  end

  def show; end

  def new
    redirect_to "/deployments/orders"
  end

  def edit
    @domains = @service.domains.sorted
    @service.master_domain = @service.domains.find_by(system_domain: true) if @service.master_domain.nil?
  end

  def update
    if @service.update(current_user.is_admin ? admin_service_params : service_params)
      redirect_to "/container_services/#{@service.id}", notice: "Service updated."
    else
      render template: "container_services/edit"
    end
  end

  def destroy
    audit = Audit.create_from_object!(@service, 'deleted', request.remote_ip, current_user)
    event = EventLog.create!(
      locale: 'service.trash',
      locale_keys: { label: @service.name },
      event_code: '859369ca114615bb',
      audit: audit,
      status: 'pending'
    )
    event.deployments << @service.deployment
    event.container_services << @service
    ContainerServiceWorkers::TrashServiceWorker.perform_async @service.to_global_id.to_s, event.to_global_id.to_s
    redirect_to (@deployment ? "/deployments/#{@deployment.token}" : "/deployments" ), notice: "Service queued for destruction."
  end

  private

  def find_service
    # @service = (current_user.is_admin ? Deployment::ContainerService : current_user.container_services).find(params[:id])
    @service = Deployment::ContainerService.find_for current_user, id: params[:id]
    return redirect_to("/deployments", alert: "Not found") if @service.nil?
    @deployment = @service.deployment
    @service.current_user = current_user
  end

  def not_found_responder
    redirect_to "/deployments", alert: "Unknown Service"
  end

  def service_params
    params.require(:deployment_container_service).permit(:label, :master_domain_id, :command, :tag_list, :image_variant_id)
  end

  def admin_service_params
    params.require(:deployment_container_service).permit(:label, :master_domain_id, :command, :tag_list, :image_variant_id, :override_autoremove)
  end

end
