class ContainerServices::ResizeServiceController < ContainerServices::BaseController

  def index
    @container_packages = BillingPackage.find_by_plan(current_user.billing_plan, {memory: @service.container_image.min_memory, cpu: @service.container_image.min_cpu})
    if @service.package.nil?
      redirect_to "/container_services/#{@service.id}", alert: "Error! This service is not associated with a package."
      return false
    elsif @container_packages.empty?
      redirect_to "/container_services/#{@service.id}", alert: "Error! There are no packages to choose from."
      return false
    end
  end

  def create
    product = Product.find_by(id: container_service_params[:package]["#{@service.image_variant.id}"])
    if product.nil?
      redirect_to "/container_services/#{@service.id}", alert: I18n.t('crud.unknown', resource: 'Product')
      return false
    end
    package = product.package
    if package.nil?
      redirect_to "/container_services/#{@service.id}", alert: I18n.t('crud.unknown', resource: 'Package')
      return false
    end
    if package == @service.package
      redirect_to "#{"/container_services/#{@service.id}"}/resize_service", alert: "Your service is already on that package."
      return false
    end
    audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
    raw_msg = {
        from: {
          product: @service.package.product&.label,
          cpu: @service.package.cpu.to_f,
          memory: @service.package.memory,
          storage: @service.package.storage,
          bandwidth: @service.package.bandwidth,
          local_disk: @service.package.local_disk
        },
        to: {
          product: package.product&.label,
          cpu: package.cpu.to_f,
          memory: package.memory,
          storage: package.storage,
          bandwidth: package.bandwidth,
          local_disk: package.local_disk
        }
    }.to_yaml
    container_count = @service.containers.count
    event = @service.event_logs.create(
        locale: (container_count.abs == 1 ? 'service.resizing_1' : 'service.resizing'),
        locale_keys: {
            'label' => @service.label,
            'count' => container_count.abs
        },
        status: 'pending',
        audit: audit,
        event_code: 'c2cf0eb058aeff2a'
    )
    event.deployments << @service.deployment if @service.deployment
    event.event_details.create!(data: raw_msg, event_code: 'c2cf0eb058aeff2a')
    ContainerServiceWorkers::ResizeServiceWorker.perform_async @service.to_global_id.to_s, event.to_global_id.to_s, package.to_global_id.to_s
    redirect_to container_service_path(@service), notice: I18n.t('container_services.controller.resize.queued')
  end

  private

  def container_service_params
    params.permit(package: {})
  end


end
