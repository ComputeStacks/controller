##
# List Project Events
class Api::Projects::EventsController < Api::Projects::BaseController

  ##
  # List all events
  #
  # `GET /api/projects/{project-id}/events`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `event_log`: Array
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
  #
  def index
    @events = paginate @deployment.event_logs.sorted
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/event_logs/index' }
    end
  end

end
