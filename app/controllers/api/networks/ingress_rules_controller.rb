##
# Network Ingress Rules API
class Api::Networks::IngressRulesController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :project_read }, unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update create destroy], unless: :current_user

  before_action :find_ingress_rule, except: :create
  before_action :find_service, only: :create

  ##
  # View Ingress Rule
  #
  # `GET /api/networks/ingress_rules/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `ingress_rule`: Object
  #     * `id`: Integer
  #     * `port`: Integer
  #     * `port_nat`: Integer
  #     * `proto`: String<http,tcp,tls,udp>
  #     * `external_access`: Boolean
  #     * `backend_ssl`: Boolean
  #     * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn>
  #     * `redirect_ssl`: Boolean
  #     * `restrict_cf`: Boolean | If true, only allow CloudFlare
  #     * `tcp_lb`: Boolean
  #     * `created_at`: Boolean
  #     * `updated_at`: Boolean
  #     * `region_id`: Integer
  #     * `container_service_id`: Integer
  #     * `load_balancer_rule_id`: Integer
  #     * `internal_load_balancer_id`: Integer
  #     * `load_balanced_rules`: Array
  #     * `links`: Object
  #         * `domains`: String (url)
  #
  def show; end

  ##
  # Update Ingress Rule
  #
  # `PATCH /api/networks/ingress_rules/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `ingress_rule`: Object
  #     * `proto`: String<http,tcp,tls,udp>
  #     * `external_access`: Boolean
  #     * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn>
  #     * `backend_ssl`: String
  #     * `port`: Integer
  #     * `restrict_cf`: Boolean | If true, only allow CloudFlare
  #     * `tcp_lb`: Boolean
  #
  def update
    params[:ingress_rule][:tcp_lb] = false if @ingress_rule.public_network? # enforce this being disabled.
    return api_obj_error(@ingress_rule.errors.full_messages) unless @ingress_rule.update(ingress_rule_params)
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/networks/ingress_rules/show', status: :accepted }
    end
  end

  ##
  # Create Ingress Rule
  #
  # `POST /api/networks/ingress_rules`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `ingress_rule`: Object
  #     * `container_service_id`: Integer | ID of Container Service, not container.
  #     * `proto`: String<http,tcp,tls,udp>
  #     * `external_access`: Boolean
  #     * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn>
  #     * `backend_ssl`: String
  #     * `port`: Integer
  #     * `restrict_cf`: Boolean | If true, only allow CloudFlare
  #     * `tcp_lb`: Boolean
  #
  def create
    @ingress_rule = @service.ingress_rules.new(create_ingress_rule_params)
    @ingress_rule.tcp_lb = false if @service.public_network?
    @ingress_rule.current_user = current_user
    @ingress_rule.region = @service.region
    return api_obj_error(@ingress_rule.errors.full_messages) unless @ingress_rule.save
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/networks/ingress_rules/show', status: :created }
    end
  rescue => e
    return api_fatal_error(e, 'bd55319e964d1f73')
  end

  ##
  # Delete Ingress Rule
  #
  # `DELETE /api/networks/ingress_rules/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  def destroy
    return api_obj_error(@ingress_rule.errors.full_messages) unless @ingress_rule.destroy
    respond_to do |format|
      format.json { render json: {}, status: :ok }
      format.xml { render xml: {}, status: :ok }
    end
  rescue => e
    return api_fatal_error(e, '303528a6b2f4806d')
  end

  private

  def find_ingress_rule
    i = Network::IngressRule.find(params[:id])
    if i.container_service
      return api_obj_missing unless i.container_service.can_edit?(current_user)
    elsif i.sftp_container&.deployment
      return api_obj_missing unless i.sftp_container.deployment.can_edit?(current_user)
    else
      # Can't edit a rule that doesn't belong to a parent obj.
      return api_obj_missing
    end
    @ingress_rule = i
    @ingress_rule.current_user = current_user
  end

  ##
  # Find ContainerService
  #
  # When creating a service, enforce the service ID and ensure
  # the user has permission to modify it.
  def find_service
    @service = Deployment::ContainerService.find_for_edit(current_user, id: create_ingress_rule_params[:container_service_id])
    return api_obj_missing if @service.nil? || !@service.can_edit?(current_user)
  end

  def ingress_rule_params
    params.require(:ingress_rule).permit(:proto, :external_access, :tcp_proxy_opt, :backend_ssl, :port, :restrict_cf, :tcp_lb)
  end

  def create_ingress_rule_params
    params.require(:ingress_rule).permit(:proto, :external_access, :tcp_proxy_opt, :backend_ssl, :port, :restrict_cf, :container_service_id, :tcp_lb)
  end

end
