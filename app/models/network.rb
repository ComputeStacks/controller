##
# Networks
#
# @!attribute name
#   The name of the network on the docker node
#   @return [String]
#
# @!attribute label
#   @return [String]
#
# @!attribute subnet
#   Note: To change the subnet, you need to force it with update_attribute, otherwise rails won't see the value
#   as having changed and will not actually update the db record.
#   @return [String]
#
# @!attribute is_shared
#   For calico deployments, it's shared with multiple projects
#   For
#   @return [Boolean]
#
# @!attribute network_driver
#   Used to aid in the migration from calico to private networks.
#   @return [String]
#
class Network < ApplicationRecord

  include Auditable
  include NetworkSubnetManager

  scope :sorted, -> { order "lower(name) DESC" }
  scope :active, -> { where active: true }
  scope :inactive, -> { where active: false }
  scope :shared, -> { where is_shared: true }
  scope :bridged, -> { where network_driver: 'bridge' }
  scope :clustered, -> { where network_driver: 'calico_docker' }

  validates :name, presence: true, uniqueness: { scope: :region_id }
  validates :label, presence: true
  validates :subnet, presence: true, uniqueness: { scope: :region_id }
  validates :network_driver, inclusion: { in: %w(calico_docker bridge) }

  validate :check_cidr_range

  belongs_to :parent_network, class_name: 'Network', foreign_key: 'parent_network_id', optional: true
  has_many :child_networks, class_name: 'Network', foreign_key: 'parent_network_id', dependent: :destroy

  belongs_to :deployment, optional: true
  belongs_to :region, optional: true

  has_one :location, through: :region
  has_many :nodes, through: :region

  has_many :addresses, class_name: 'Network::Cidr', dependent: :restrict_with_error

  before_save :format_network_name

  def to_net
    "#{subnet.to_s}/#{subnet.prefix}"
  end

  def to_addr
    # https://www.rubydoc.info/gems/netaddr
    NetAddr::IPv4Net.parse to_net
  end

  def has_clustered_networking?
    network_driver == 'calico_docker'
  end

  def docker_client(node)
    Docker::Network.get(name, {}, node.client(3))
  rescue Docker::Error::NotFoundError
    nil
  rescue => e
    SystemEvent.create!(
      message: "Fatal error connecting to node",
      data: {
        node: node&.label,
        network: {
          id: id,
          name: name
        },
        error: e.message
      },
      event_code: "37f551c1ebb1e831"
    )
    nil
  end

  ##
  # Does the network exist on the node?
  def network_exists?(node)
    docker_client(node).is_a? Docker::Network
  end

  def addresses_available
    to_addr.len - addresses_in_use.count
  end

  # @return [Array<Integer>]
  def addresses_in_use
    a = to_addr
    # network, gateway, broadcast
    in_use = [a.nth(0).addr, a.nth(1).addr, a.nth(a.len - 1).addr]
    addresses.each do |i|
      in_use << i.cidr.to_i
    end
    in_use
  end

  private

  def check_cidr_range
    errors.add(:subnet, 'Only IPv4 is enabled.') if subnet.ipv6?
    errors.add(:subnet, 'Must be at least a /29') if subnet.to_range.count < 16
    # Check for private ranges
    case subnet.to_s.split('.').first.to_i
    when 10
      errors.add(:subnet, 'Must be a private IP range. 10.x networks need to be within 10.0.0.0/8.') unless IPAddr.new('10.0.0.0/8').include?(subnet)
    when 172
      errors.add(:subnet, 'Must be a private IP range. 172.x networks need to be within 172.16.0.0/12.') unless IPAddr.new('172.16.0.0/12').include?(subnet)
    when 192
      errors.add(:subnet, 'Must be a private IP range. 192.x networks need to be within 192.168.0.0/16.') unless IPAddr.new('192.168.0.0/16').include?(subnet)
    else
      errors.add(:subnet, 'Must be a private IP range')
    end
  rescue
    errors.add(:cidr)
  end

  def format_network_name
    self.name = name.strip.downcase.gsub(/[^0-9A-Za-z]/, '')
  end

end
