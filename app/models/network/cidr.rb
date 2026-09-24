##
# Network Cidr (IPAddress)
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute cidr
#   @return [Inet]
#
# @!attribute container
#   @return [Deployment::Container]
#
# @!attribute sftp_container
#   @return [Deployment::Sftp]
#
class Network::Cidr < ApplicationRecord
  belongs_to :network
  has_one :region, through: :network

  belongs_to :container, class_name: "Deployment::Container", inverse_of: :ip_address, optional: true
  belongs_to :sftp_container, class_name: "Deployment::Sftp", inverse_of: :ip_address, optional: true

  before_create :set_ip_addr!

  def csrn
    "csrn:caas:project:cidr:#{resource_name}:#{id}"
  end

  def resource_name
    return "null" if cidr.blank?
    cidr.to_s.strip.tr(".", "-")
  end

  def ipaddr
    cidr.to_s
  end

  def release!
    n = nil
    n = container.node if container
    n = sftp_container.node if sftp_container
    return false if n.nil?

    Network::Cidr.release! n, cidr.to_s
  end

  # @param [Node] node
  # @param [String] ip
  # @return [Boolean]
  def self.release!(node, ip)
    return true unless node.region.has_clustered_networking?
    return false if ip.nil? || node.nil?

    release_command = "calicoctl ipam release --ip=#{ip}"
    node.host_client.client.exec!(release_command)
  rescue => e
    ExceptionAlertService.new(e, "a596b3bc986d5ec5").perform
    false
  end

  private

  def set_ip_addr!
    if cidr.blank?
      self.cidr = network.next_ip
    end
  end
end
