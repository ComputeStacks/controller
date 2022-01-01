##
# Container Service SSL Certificates
class Api::ContainerServices::SslController < Api::ContainerServices::BaseController

  before_action :load_certificate, only: %i[ destroy show update]

  ##
  # List SSL Certificates
  #
  # Custom certificates only
  #
  # `GET /api/container_services/{container-service-id}/ssl`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `certificates`: Array
  #     * `id`: Integer
  #     * `cert_serial`: String
  #     * `issuer`: String
  #     * `subject`: String
  #     * `not_before`: DateTime
  #     * `not_after`: DateTime
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @certificates = paginate @service.ssl_certificates
  end

  ##
  # View SSL Certificate
  #
  # `GET /api/container_services/{container-service-id}/ssl/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `certificates`: Object
  #     * `id`: Integer
  #     * `cert_serial`: String
  #     * `issuer`: String
  #     * `subject`: String
  #     * `not_before`: DateTime
  #     * `not_after`: DateTime
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Create SSL Certificate
  #
  # `POST /api/container_services/{container-service-id}/ssl`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `certificate`: Object
  #     * `ca`: String
  #     * `crt`: String
  #     * `pkey`: String
  #
  def create
    @certificate = @service.ssl_certificates.new(certificate_params)
    @certificate.current_user = current_user
    respond_to do |format|
      if @certificate.valid? && @certificate.save
        format.json { render json: {}, status: :created }
        format.json { render xml: {}, status: :created }
      else
        format.json { render json: {errors: @certificate.errors}, status: :bad_request }
        format.xml { render xml: {errors: @certificate.errors}, status: :bad_request }
      end
    end
  rescue => e
    return api_fatal_error(e, 'f4e7b07e027e5304')
  end

  ##
  # Delete certificate
  #
  # `DELETE /api/container_services/{container-service-id}/ssl/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  def destroy
    respond_to do |format|
      if @certificate.destroy
        if @service.load_balancer
          LoadBalancerServices::DeployConfigService.new(@service.load_balancer).perform
        end
        format.json { render json: {}, status: :accepted }
        format.xml { render xml: {}, status: :accepted }
      else
        format.json { render json: {errors: @certificate.errors}, status: :internal_server_error }
        format.xml { render xml: {errors: @certificate.errors}, status: :internal_server_error }
      end
    end
  rescue => e
    return api_fatal_error(e, '7533e1a2059b4530')
  end

  private

  ##
  # =Allowed certificate attributes
  def certificate_params # :doc:
    params.require(:certificate).permit(:crt, :ca, :pkey)
  end

  ##
  # =Load certificate helper
  def load_certificate # :doc:
    @certificate = @service.ssl_certificates.find_by(id: params[:id])
    return api_obj_missing if @certificate.nil?
    @certificate.current_user = current_user
  end

end
