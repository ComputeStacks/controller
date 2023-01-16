class ContainerServices::ScaleServiceController < ContainerServices::BaseController

  def create
    audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
    event = @service.event_logs.create(
        locale: 'service.scaling',
        locale_keys: {
            'label' => @service.label,
            'from' => @service.containers.count,
            'to' => params[:qty].to_i
        },
        status: 'pending',
        audit: audit,
        event_code: '16fb2bd5a38082ee'
    )
    event.deployments << @service.deployment if @service.deployment
    ContainerServiceWorkers::ScaleServiceWorker.perform_async @service.global_id, event.global_id
    redirect_to container_service_path(@service), notice: I18n.t('crud.queued_plural', resource: I18n.t('obj.containers'))
  end

end
