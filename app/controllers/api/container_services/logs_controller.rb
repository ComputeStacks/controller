##
# Container Service Logs
class Api::ContainerServices::LogsController < Api::ContainerServices::BaseController

  ##
  # View Recent Logs
  #
  # `GET /api/container_services/{id}/logs`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `limit`: Integer | How many lines to include?
  # * `period_start`: Integer | Log date range (start). As an integer, time since epoch. Default: 1 day ago
  # * `period_end`: Integer | Log date range (end). As an integer, time since epoch. Default: Now
  #
  # Returns an Array of Arrays containing: Timestamp, container name, log entry
  #
  # @example
  #     [
  #        [
  #          1612904254.9995728,
  #          "mystifying-poincare61-104",
  #          "t=2021-02-09T20:57:34+0000 lvl=info msg=\"HTTP Server Listen\" logger=http.server address=[::]:3000 protocol=http subUrl= socket="
  #        ],
  #        [
  #          1612904254.991145,
  #          "mystifying-poincare61-104",
  #          "t=2021-02-09T20:57:34+0000 lvl=info msg=\"Registering plugin\" logger=plugins id=input"
  #        ],
  #        [
  #          1612904254.8895183,
  #          "mystifying-poincare61-104",
  #          "t=2021-02-09T20:57:34+0000 lvl=info msg=\"Starting plugin search\" logger=plugins"
  #        ]
  #      ]
  #
  def index
    limit = params[:limit].to_i > 0 ? params[:limit] : 500
    period_start = params[:period_start].to_i > 0 ? Time.at(params[:period_start].to_i) : 1.day.ago
    period_end = params[:period_end].to_i > 0 ? Time.at(params[:period_end].to_i) : Time.now
    @logs = @service.logs(period_start, period_end, limit)
    respond_to do |format|
      format.json { render json: @logs }
      format.xml { render xml: @logs }
    end
  end

end
