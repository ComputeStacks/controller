class ContainerServices::Wordpress::ProtectController < ContainerServices::Wordpress::BaseController

  before_action :load_protected_action

  def index
    if request.xhr?
      @protect = ContainerServices::WordpressServices::ProtectedService.new(@service)
      @enabled = @protect.enabled?
      render layout: false
    end
  end

  def create
    audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
    event = EventLog.create!(
      locale_keys: { service: @service.name},
      status: "pending",
      locale: "wordpress.protect.enable",
      event_code: "335563f649792690",
      audit: audit
    )
    event.container_services << @service
    event.deployments << @service.deployment
    @p.event = event
    if @p.enable!
      flash[:notice] = "Protect mode disabled"
    else
      flash[:alert] = @p.errors.join(" ")
    end
    redirect_to "/container_services/#{@service.id}"
  end

  def destroy
    audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
    event = EventLog.create!(
      locale_keys: { service: @service.name},
      status: "pending",
      locale: "wordpress.protect.disable",
      event_code: "766c5a3c0e47dd96",
      audit: audit
    )
    event.container_services << @service
    event.deployments << @service.deployment
    @p.event = event
    if @p.disable!
      flash[:notice] = "Protect mode disabled"
    else
      flash[:alert] = @p.errors.join(" ")
    end
    redirect_to "/container_services/#{@service.id}"
  end

  private

  def load_protected_action
    @p = ContainerServices::WordpressServices::ProtectedService.new(@service)
  end



end
