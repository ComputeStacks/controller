##
# Scale a container service
class Api::ContainerServices::ScaleController < Api::ContainerServices::BaseController

  ##
  # Initiate a scale event for a ContainerService
  #
  # `POST /api/container_services/{container-service-id}/scale`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `qty`: Integer | The total number of containers this service should have #
  #
  # @example
  #    {
  #      "container_service": {
  #        "qty": 2
  #      }
  #    }
  #
  def create
    audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
    event = @service.event_logs.create(
      locale: 'service.scaling',
      locale_keys: {
        'label' => @service.label,
        'from' => @service.containers.count,
        'to' => container_service_params[:qty].to_i
      },
      status: 'pending',
      audit: audit,
      event_code: 'c2dcdabd7101caa5'
    )
    event.deployments << @service.deployment if @service.deployment
    errors = []
    redirect_url = nil
    region_check = @service.region
    if region_check && !region_check.nodes.empty?
      ContainerServiceWorkers::ScaleServiceWorker.perform_async @service.global_id, event.global_id
    else
      errors << 'Invalid Region. Unable to scale containers.'
    end
    respond_to do |format|
      if errors.empty? && redirect_url.nil?
        format.json { render json: {}, status: :accepted }
        format.xml { render xml: {}, status: :accepted }
      elsif !errors.empty?
        format.json { render json: {errors: errors}, status: :unprocessable_entity }
        format.xml { render xml: {errors: errors}, status: :unprocessable_entity }
      elsif !redirect_url.nil?
        format.json { render json: {
          order: {
            id: SecureRandom.uuid,
            status: 'awaiting_payment',
            redirect_url: redirect_url
          },
          container_service: {
            id: @service.id
          }
        }}
        format.xml { render xml: {
          order: {
            id: SecureRandom.uuid,
            status: 'awaiting_payment',
            redirect_url: redirect_url
          },
          container_service: {
            id: @service.id
          }
        }}
      end
    end
  rescue => e
    return api_fatal_error(e, '15b574a17e0ac387')
  end

  private

  def container_service_params
    params.require(:container_service).permit(:qty)
  end

end
