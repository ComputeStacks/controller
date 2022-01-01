##
# Container CPU Statistics
class Api::Containers::Metrics::CpuController < Api::Containers::BaseController

  ##
  # View Container CPU Statistics
  #
  # Both the time, and date/memory label and format, will be formatted to match your API user's timezone and locale.
  #
  # `GET /api/containers/{container-id}/metrics/cpu`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `stats`: Array
  #
  # @example
  #    {
  #      "stats": [
  #        [ "2021-03-11T21:55:51.000+00:00", 0.22]
  #      ]
  #    }
  #
  def index
    @stats = @container.metric_cpu_usage(3.hours.ago, Time.now)
    respond_to do |f|
      f.json { render json: { stats: @stats } }
      f.xml { render xml: { stats: @stats } }
    end
  rescue => e
    api_obj_error e.message
  end

end
