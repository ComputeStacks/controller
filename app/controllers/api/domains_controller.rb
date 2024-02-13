##
# Project Domains API
class Api::DomainsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update create destroy], unless: :current_user

  before_action :load_domain, except: %i[ index create ]

  ##
  # List all domains
  #
  # `GET /api/domains`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `domains`: Array
  #     * `id`: Integer
  #     * `domain`: String
  #     * `system_domain`: Boolean
  #     * `header_hsts`: Boolean
  #     * `force_https`: Boolean
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `container_service`: Integer
  #     * `lets_encrypt`: String<active,pending,inactive>
  #     * `links`: Hash
  #         * `container_service`: String (url)
  #
  def index
    @domains = paginate current_user.container_domains
  end

  ##
  # View domain
  #
  # `GET /api/domains/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `domain`: Object
  #     * `id`: Integer
  #     * `domain`: String
  #     * `system_domain`: Boolean
  #     * `le_enabled`: Boolean
  #     * `ingress_rule_id`: Integer
  #     * `force_https`: Boolean
  #     * `header_hsts`: Boolean
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `container_service`: Integer
  #     * `lets_encrypt`: String<active,pending,inactive>
  #     * `links`: Hash
  #         * `container_service`: String (url)
  #
  def show; end

  ##
  # Create Domain
  #
  # `POST /api/domains`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `domain`: Object
  #     * `domain`: String
  #     * `le_enabled`: Boolean
  #     * `make_primary`: Boolean
  #     * `heder_hsts`: Boolean
  #     * `ingress_rule_id`: Integer
  #     * `make_primary`: Boolean
  #
  def create
    @domain = current_user.container_domains.new(domain_params)
    @domain.current_user = current_user
    return api_obj_error(['missing domain route']) if @domain.ingress_rule.nil?
    return api_obj_error(@domain.errors.full_messages) unless @domain.save

    # Make primary
    @domain.update(make_primary: true) if domain_params[:make_primary]

    respond_to do |format|
      format.any(:json, :xml) { render action: :show }
    end
  rescue => e
    return api_fatal_error(e, '2e2abaf920847b09')
  end

  ##
  # Update Domain
  #
  # `PATCH /api/domains/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `domain`: Object
  #     * `domain`: String
  #     * `le_enabled`: Boolean
  #     * `heder_hsts`: Boolean
  #     * `force_https`: Boolean
  #     * `ingress_rule_id`: Integer
  #
  def update
    return api_obj_error(["Can't update system domains."]) if @domain.system_domain
    return api_obj_error(@domain.errors.full_messages) unless @domain.update(domain_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show }
    end
  rescue => e
    return api_fatal_error(e, '78c6da0cad97261d')
  end

  ##
  # Delete Domain
  #
  # `DELETE /api/domains/{id}`
  #
  def destroy
    return api_obj_error(["Can't remove system domains."]) if @domain.system_domain
    respond_to do |format|
      if @domain.destroy
        format.json { render json: {}, status: :accepted }
        format.xml { render xml: {}, status: :accepted }
      else
        format.json { render json: {errors: @domain.errors}, status: :bad_request }
        format.xml { render xml: {errors: @domain.errors}, status: :bad_request }
      end
    end
  rescue => e
    return api_fatal_error(e, 'b392ad8e9fd57404')
  end

  private

  def domain_params
    params.require(:domain).permit(
      :domain, :le_enabled, :ingress_rule_id, :header_hsts, :make_primary, :force_https
    )
  end

  def load_domain
    @domain = Deployment::ContainerDomain.find_for current_user, id: params[:id]
    return api_obj_missing if @domain.nil?
    @domain.current_user = current_user
  end

end
