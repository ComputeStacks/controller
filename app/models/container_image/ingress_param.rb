##
# ContainerImage Ingress Param
#
# @!attribute backend_ssl
#   @return [Boolean] If true, HAProxy will connect to your container via SSL.
#
# @!attribute external_access
#   @return [Boolean] If true, external access to this ingress rule will be allowed.
#
# @!attribute port
#   @return [Integer] Internal port of container
#
# @!attribute proto
#   @return [http,tcp,tls,udp] `tls` is only possible when `tcp_lb` is true.
#
# @!attribute tcp_proxy_opt
#   @return [none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn]
#
# @!attribute tcp_lb
#   @return [Boolean] False will use local iptable rules (NAT). `tls` is not possible.
#
class ContainerImage::IngressParam < ApplicationRecord

  include Auditable
  include IngressValidator

  scope :sorted, -> { order(:port) }

  has_many :dependent_params, class_name: 'Network::IngressRule', foreign_key: 'ingress_param_id', dependent: :nullify

  belongs_to :container_image
  belongs_to :load_balancer_rule, class_name: 'ContainerImage::IngressParam', optional: true
  has_one :internal_load_balancer, through: :load_balancer_rule, source: :container_image

  validates :port, uniqueness: { scope: :container_image_id, message: "port is already assigned to container image" }

  validate :custom_load_balancer

  # Helper method since our forms are shared between both ingress rules and ingress params.
  def public_network?
    false
  end

  private

  def custom_load_balancer
    if load_balancer_rule && !load_balancer_rule.container_image.is_load_balancer
      errors.add(:load_balancer_image_id, 'is not a load balancer')
    end
  end

end
