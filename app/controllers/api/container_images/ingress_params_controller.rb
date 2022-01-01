##
# Image Ingerss Parameters
class Api::ContainerImages::IngressParamsController < Api::ContainerImages::BaseController

  before_action :find_ingress_rule, only: [:show, :update, :destroy]

  ##
  # List all ingress params for a given image
  #
  # `GET /api/container_images/{container-image-id}/ingress_params`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `ingress_params`: Array
  #     * `port`: Integer
  #     * `proto`: String<tcp,udp,tls>
  #     * `backend_ssl`: Boolean
  #     * `external_access`: Boolean
  #     * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn>
  #     * `tcp_lb`: Boolean
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #     * `load_balancer_id`: Integer
  #     * `internal_load_balancer_id`: Integer
  #
  def index
    @ingress_params = @image.ingress_params
  end

  ##
  # View a single ingress param
  #
  # `GET /api/container_images/{container-image-id}/ingress_params/{id}`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `ingress_param`: Object
  #     * `port`: Integer
  #     * `proto`: String<tcp,udp,tls>
  #     * `backend_ssl`: Boolean
  #     * `external_access`: Boolean
  #     * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn>
  #     * `tcp_lb`: Boolean
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #     * `load_balancer_id`: Integer
  #     * `internal_load_balancer_id`: Integer
  #
  def show; end

  ##
  # Update an ingress param
  #
  # `PATCH /api/container_images/{container-image-id}/ingress_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `ingress_param`: Object
  #     * `port`: Integer
  #     * `proto`: String<tcp,udp,tls>
  #     * `external_access`: Boolean
  #     * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn> | Ensure your backend supports the `PROXY` protocol before enabling this.
  #     * `backend_ssl`: Boolean
  #
  def update
    if @ingress_param.update(ingress_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @ingress_param.errors.full_messages
    end
  end

  ##
  # Create an ingress param
  #
  # `POST /api/container_images/{container-image-id}/ingress_params`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `ingress_param`: Object
  #     * `port`: Integer
  #     * `proto`: String<tcp,udp,tls>
  #     * `external_access`: Boolean
  #     * `tcp_proxy_opt`: String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn> | Ensure your backend supports the `PROXY` protocol before enabling this.
  #     * `backend_ssl`: Boolean
  #
  def create
    @ingress_param = @image.ingress_params.new(ingress_params)
    @ingress_param.current_user = current_user
    if @ingress_param.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @ingress_param.errors.full_messages
    end
  end

  ##
  # Delete an ingress param
  #
  # `DELETE /api/container_images/{container-image-id}/ingress_params/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    @ingress_param.destroy ? api_obj_destroyed : api_obj_error(@ingress_param.errors.full_messages)
  end

  private

  def find_ingress_rule
    @ingress_param = @image.ingress_params.find_by(id: params[:id])
    return api_obj_missing if @ingress_param.nil?
    @ingress_param.current_user = current_user
  end

  def ingress_params
    params.require(:ingress_param).permit(:port, :proto, :backend_ssl, :external_access, :tcp_proxy_opt)
  end


end
