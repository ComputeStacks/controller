##
# Resize Container Service
class Api::ContainerServices::ResizeController < Api::ContainerServices::BaseController

  ##
  # Initiate a resize event for a ContainerService
  #
  # `POST /api/container_services/{container-service-id}/resize`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `product_id`: Integer | New plan
  #
  # @example
  #      {
  #        "container_service": {
  #          "product_id": 2
  #        }
  #      }
  #
  def create
    errors = []
    redirect_url = [] # While we are creating an array, we expect our billing platforms to only return a single redirectUrl. We will only present the last one to the user
    result = []
    product = Product.find_by(id: container_service_params[:product_id])
    if product&.package
      unless product.package == @service.package # Don't do anything if nothing will change.
        audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
        raw_msg = {
          product: product.label,
          cpu: product.package&.cpu,
          memory: product.package&.memory,
          storage: product.package&.storage,
          bandwidth: product.package&.bandwidth
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
          event_code: 'fdfcc55ffebd0424'
        )
        event.event_details.create!(data: raw_msg, event_code: 'fdfcc55ffebd0424')
        event.deployments << @service.deployment if @service.deployment
        ContainerServiceWorkers::ResizeServiceWorker.perform_async(
          @service.to_global_id.to_s,
          event.to_global_id.to_s,
          product.package.to_global_id.to_s
        )
        result << "Successfully queued resize to package #{product.label}"
      end
    else
      errors << "Missing package id: #{container_service_params[:product_id]}"
    end # END if package
    respond_to do |format|
      if errors.empty? && redirect_url.empty?
        format.json { render json: {}, status: :accepted }
        format.xml { render xml: {}, status: :accepted }
      elsif !errors.empty?
        format.json { render json: {errors: errors}, status: :unprocessable_entity }
        format.xml { render xml: {errors: errors}, status: :unprocessable_entity }
      elsif !redirect_url.empty?
        format.json { render json: {
          order: {
            id: SecureRandom.uuid,
            status: 'awaiting_payment',
            redirect_url: redirect_url.last
          },
          container_service: {
            id: @service.id
          }
        }}
        format.xml { render xml: {
          order: {
            id: SecureRandom.uuid,
            status: 'awaiting_payment',
            redirect_url: redirect_url.last
          },
          container_service: {
            id: @service.id
          }
        }}
      end
    end
  rescue => e
    return api_fatal_error(e, '7edfcd7b18061cba')
  end

  private

  def container_service_params
    params.require(:container_service).permit(:product_id)
  end

end
