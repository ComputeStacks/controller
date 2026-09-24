##
# Project Metrics
class Api::Projects::MetricsController < Api::Projects::BaseController
  # A POST only because the request carries an array of metric kinds; it reads
  # and returns metrics without changing anything, and has always been
  # documented as needing read access. It would otherwise inherit
  # `project_write` from the base controller's `write:` declaration.
  api_scope create: :project_read

  ##
  # List Metrics for this project
  #
  # `POST /api/project/{project-id}/metrics`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # kind can be one or more of:
  #   - cpu
  #   - cpu_throttled
  #   - memory
  #   - memory_throttled
  #   - storage
  #
  # @params
  #   * `kind`: Array | ['storage', 'memory'] (example)
  #   * `period_start`: Integer | unix timestamp
  #   * `period_end`: Integer | unix timestamp
  #   * `step`: String | defaults to '1m'.
  #
  # Period and Step parameters have no affect on storage metric. That will always return the current value.
  #
  # * `service_name`: Object
  #   * `id`: Integer
  #   * `name`: String
  #   * `image`: String
  #   * `resources`: Object | Dependent on which values selected
  #       * `cpu`: Array<time, value>
  #       * `cpu_throttled`: Array<time, value>
  #       * `memory`: Array<time, value>
  #       * `memory_throttled`: Array<time, value>
  #       * `storage`: Decimal
  #
  def create

    @data = {}

    requested_resources = metric_params[:kind]
    unless requested_resources.is_a?(Array)
      return api_obj_error('Invalid kind. Must be type Array')
    end

    period_start = if metric_params[:period_start]
      Time.at(metric_params[:period_start])
    else
      3.hours.ago
    end
    period_end = if metric_params[:period_end]
      Time.at(metric_params[:period_end])
    else
      Time.now
    end
    period_step = if metric_params[:step]
      metric_params[:step]
    else
      '5m'
    end

    @deployment.services.each do |service|
      @data[service.name] = {
        id: service.id,
        name: service.name,
        image: service.container_image.label,
        resources: { 
          cpu: [],
          cpu_throttled: [],
          memory: [],
          memory_throttled: [],
          storage: nil
        }
      }

      if requested_resources.include?('cpu')
        @data[service.name][:resources][:cpu] = service.metric_cpu_usage(period_start, period_end, period_step)
      end
      if requested_resources.include?('cpu_throttled')
        @data[service.name][:resources][:cpu_throttled] = service.metric_cpu_throttled(period_start, period_end, period_step)
      end
      if requested_resources.include?('memory')
        @data[service.name][:resources][:memory] = service.metric_mem_usage(period_start, period_end, period_step)
      end
      if requested_resources.include?('memory_throttled')
        @data[service.name][:resources][:memory_throttled] = service.metric_mem_throttled(period_start, period_end, period_step)
      end
      if requested_resources.include?('storage')
        @data[service.name][:resources][:storage] = service.current_storage.round(2)
      end

    end

    respond_to do |f|
      f.json { render json: @data }
      f.xml { render xml: @data }
    end
  rescue => e
    api_obj_error e.message
  end

  private

  def metric_params
    params.permit(:period_start, :period_end, :step, kind: [])
  end


end
