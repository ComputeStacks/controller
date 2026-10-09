##
# Scale a container service
class Api::ContainerServices::ScaleController < Api::ContainerServices::BaseController
  ##
  # Initiate a scale event for a ContainerService
  #
  # `POST /api/container_services/{container-service-id}/scale`
  #
  # **OAuth AuthorizationRequired**: `project_write`
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
  # Responds `202 Accepted` with an empty body; the scale runs in the background.
  #
  # Adding containers needs an available node in the service's region. When there is
  # none because the region's nodes are in maintenance or offline, nothing is changed and
  # the response is `409 Conflict` with `errors`, `code` (`node_maintenance` or
  # `node_offline`) and the region's `node_status`. Scaling down is not refused this way.
  #
  def create
    if (refusal = scale_up_refusal)
      return api_node_unavailable([refusal[:message]], code: refusal[:code], node_status: refusal[:node_status])
    end
    audit = Audit.create_from_object!(@service, "updated", request.remote_ip, current_user)
    event = @service.event_logs.create(
      locale: "service.scaling",
      locale_keys: {
        "label" => @service.label,
        "from" => @service.containers.count,
        "to" => container_service_params[:qty].to_i
      },
      status: "pending",
      audit: audit,
      event_code: "c2dcdabd7101caa5"
    )
    event.deployments << @service.deployment if @service.deployment
    errors = []
    redirect_url = nil
    region_check = @service.region
    if region_check && !region_check.nodes.empty?
      ContainerServiceWorkers::ScaleServiceWorker.perform_async @service.global_id, event.global_id
    else
      errors << "Invalid Region. Unable to scale containers."
    end
    respond_to do |format|
      if errors.empty? && redirect_url.nil?
        format.json { render json: {}, status: :accepted }
        format.xml { render xml: {}, status: :accepted }
      elsif !errors.empty?
        format.json { render json: {errors: errors}, status: :unprocessable_entity }
        format.xml { render xml: {errors: errors}, status: :unprocessable_entity }
      elsif !redirect_url.nil?
        format.json {
          render json: {
            order: {
              id: SecureRandom.uuid,
              status: "awaiting_payment",
              redirect_url: redirect_url
            },
            container_service: {
              id: @service.id
            }
          }
        }
        format.xml {
          render xml: {
            order: {
              id: SecureRandom.uuid,
              status: "awaiting_payment",
              redirect_url: redirect_url
            },
            container_service: {
              id: @service.id
            }
          }
        }
      end
    end
  rescue => e
    api_fatal_error(e, "15b574a17e0ac387")
  end

  private

  # A scale-up needs a node to place the new containers on (Region#find_node picks from
  # `nodes.available`). Refuse up front when the region has none because of maintenance
  # or an outage, rather than leave an event that fails in the worker.
  #
  # @return [Hash, nil] message, code and node_status, or nil to proceed
  def scale_up_refusal
    region = @service.region
    return nil if region.nil? || region.nodes.empty? # "Invalid Region" below, as before
    return nil unless container_service_params[:qty].to_i > @service.containers.count
    return nil if region.nodes.available.exists?

    node_status = Nodes::CustomerStatusPresenter.for_region(region)
    code = Nodes::CustomerStatusPresenter.code_for(node_status["state"])
    return nil if code.nil? # defensive: the rollup says online, so behave as before
    message = if code == "node_maintenance"
      "The nodes in this service's region are in maintenance; try again once it ends."
    else
      "The nodes in this service's region are offline."
    end
    {message: message, code: code, node_status: node_status}
  end

  def container_service_params
    params.require(:container_service).permit(:qty)
  end
end
