##
# EventLogs API
class Api::EventLogsController < Api::ApplicationController
  api_scope show: :project_read

  before_action :load_event, only: :show

  ##
  # View Event Log
  #
  # `GET /api/event_logs/{id}`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `event_log`: Object
  #     * `id`: Integer
  #     * `locale`: String
  #     * `status`: String
  #     * `notice`: Boolean
  #     * `state_reason`: String
  #     * `event_code`: String
  #     * `description`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `audit`: Object
  #         * `id`: Integer
  #         * `ip_addr`: String
  #         * `event`: String
  #         * `raw_data`: String
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #         * `user`: Object
  #             * `id`: Integer
  #             * `name`: String
  #     * `event_details`: Array
  #         * `id`: Integer
  #         * `data`: String
  #         * `event_code`: String
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #
  def show
  end

  private

  def load_event
    @event = EventLog.find_for_user params[:id], current_user
    api_obj_missing if @event.nil?
  end
end
