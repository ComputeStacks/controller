##
# Containers API
class Api::ContainersController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[show events], unless: :current_user

  before_action :load_container

  ##
  # View Container
  #
  # `GET /api/containers/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  #
  # * `containers`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `req_state`: String<running,stopped>
  #     * `stats`: Object
  #         * `cpu`: Decimal
  #         * `mem`: Decimal
  #     * `current_state`: String<migrating,starting,stopping,working,alert,resource_usage,online,offline>
  #     * `local_ip`: String
  #     * `public_ip`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `ingress_rules`: Array
  #         * `ingress_rule`: Object
  #             * `id`: Integer
  #             * `port`: Integer
  #             * `port_nat`: Integer
  #             * `proto`: String<http,tcp,tls,udp>
  #             * `external_access`: Boolean
  #             * `backend_ssl`: Boolean
  #             * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn>
  #             * `redirect_ssl`: Boolean
  #             * `restrict_cf`: Boolean | If true, only allow CloudFlare
  #             * `tcp_lb`: Boolean
  #             * `created_at`: Boolean
  #             * `updated_at`: Boolean
  #             * `container_service_id`: Integer
  #             * `load_balancer_rule_id`: Integer
  #             * `internal_load_balancer_id`: Integer
  #             * `load_balanced_rules`: Array
  #             * `links`: Object
  #                 * `domains`: String (url)
  #
  def show; end

  private

  def load_container # :doc:
    @container = Deployment::Container.find_for current_user, id: params[:id]
    return api_obj_missing if @container.nil?
    if params[:include] && params[:include] == "logs"
      limit = params[:limit].to_i > 0 ? params[:limit] : 500
      period_start = params[:period_start].to_i > 0 ? Time.at(params[:period_start].to_i) : 1.day.ago
      period_end = params[:period_end].to_i > 0 ? Time.at(params[:period_end].to_i) : Time.now
      @logs = @container.logs(period_start, period_end, limit)
      @logs = @logs.map {|i| [Time.at(i[0]),i[1].gsub('/',''),i[2]]} if params[:date_string]
    end
  end

end
