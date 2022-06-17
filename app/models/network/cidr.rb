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

  belongs_to :container, class_name: 'Deployment::Container', inverse_of: :ip_address, optional: true
  belongs_to :sftp_container, class_name: 'Deployment::Sftp', inverse_of: :ip_address, optional: true
  # belongs_to :load_balancer, foreign_key: 'rel_id', class_name: 'LoadBalancer', inverse_of: :ip_address, optional: true

  before_create :set_ip_addr!

  def csrn
    "csrn:caas:project:cidr:#{resource_name}:#{id}"
  end

  def resource_name
    return "null" if cidr.blank?
    cidr.to_s.strip.gsub(".","-")
  end

  def ipaddr
    cidr.to_s
  end

  def self.release!(node, ip)
    return false if ip.nil? || node.nil?
    release_command = "calicoctl ipam release --ip=#{ip}"
    result = node.host_client.client.exec!(release_command)
    result
    # true
  rescue => e
    ExceptionAlertService.new(e, 'a596b3bc986d5ec5').perform
    false
  end

  private

  def set_ip_addr!
    if cidr.blank?
      self.cidr = "#{network.next_ip}/32"
    end
  end

end
