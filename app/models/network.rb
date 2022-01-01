##
# Networks
#
# cdir:string
# is_public:boolean
#
# https://docs.ruby-lang.org/en/2.0.0/Range.html
# https://docs.ruby-lang.org/en/2.0.0/IPAddr.html
#
# http://docs.projectcalico.org/v2.1/usage/troubleshooting/faq#how-can-i-enable-nat-for-incoming-traffic-to-containers-with-private-ip-addresses
#
class Network < ApplicationRecord

  include Auditable

  scope :sorted, -> { order(Arel.sql("lower(name) DESC, lower(label) DESC")) }
  scope :public_net, -> { where is_public: true }

  validates :name, presence: true
  validates :label, presence: true
  validates :cidr, presence: true

  validate :check_cidr_range

  has_and_belongs_to_many :regions
  has_many :locations, -> { distinct }, through: :regions
  has_many :nodes, through: :regions

  has_many :addresses, class_name: 'Network::Cidr', dependent: :restrict_with_error


  before_save :check_ip_type
  before_save :format_network_name

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

  ##
  # Active IPs in use on Node.
  #
  # Load directly from docker the raw, in use, ip addresses. Regardless of what CS says.
  # Short expiration on cache -- we want close to real time data, but if we're deploying a lot of containers
  # really quickly, lets not kill the docker daemon with requests over this.
  #
  def active_in_use
    # return [] if Rails.env.test?
    Rails.cache.fetch("net_#{id}_ips", expires_in: 90.seconds, unless: lambda { |i| i.empty? }) do
      node_check = nodes.available.first
      return [] if node_check.nil?
      used_on_node = Timeout::timeout(2) do
        docker_client(node_check)
      end
      return [] if used_on_node.nil? || used_on_node.info.nil?
      Timeout::timeout(5) do
        used_on_node.info['Containers'].values.map { |i| i['IPv4Address'].gsub("/32", "") }
      end
    end
  rescue Timeout::Error => e
    n = nodes.available.first
    if n.nil?
      Rails.logger.warn %Q(message="Error connecting to docker daemon" error=#{e.message})
    else
      Rails.logger.warn %Q(message="Error connecting to docker daemon" host=#{n.hostname} error=#{e.message})
    end
    []
  rescue => e
    ExceptionAlertService.new(e, 'f937f614d1593fa6').perform
    []
  end


  ##
  # Find next available IP
  def next_ip
    range = IPAddr.new(cidr).to_range

    # Bring some randomness into the ip selection process.
    rstep = rand(1..3)
    flip_check = rand(1..2).even?

    if flip_check
      range.step(rstep).each do |addr|
        reload
        used = addresses.pluck(:cidr)
        used_on_node = active_in_use
        next if restricted?(addr)
        next if used_on_node.include?(addr)
        return addr.to_s unless used.include?("#{addr}/32")
      end
    else
      range.step(rstep).reverse_each do |addr|
        reload
        used = addresses.pluck(:cidr)
        used_on_node = active_in_use
        next if restricted?(addr)
        next if used_on_node.include?(addr)
        return addr.to_s unless used.include?("#{addr}/32")
      end
    end
    nil
  end

  # @param [String] endpoint
  # @param [Node] req_node
  #
  # [root@ch02 ~]# docker start youthful-jennings640
  # Error response from daemon: endpoint with name youthful-jennings640 already exists in network net100
  # Error: failed to start containers: youthful-jennings640
  #
  # docker rm <container-name>
  # docker network disconnect --force <network-name> <container-name>
  #
  # def disconnect!(endpoint, req_node = nil)
  #   return false if endpoint.nil?
  #   req_node = self.nodes.available.first
  #   req_node.host_client.client.exec!("docker network disconnect --force #{self.name} #{endpoint}")
  # end

  private

  def check_cidr_range
    ipaddr = IPAddr.new(self.cidr)
    errors.add(:cidr, 'Only IPv4 is enabled.') if ipaddr.ipv6?
    errors.add(:cidr, 'Must be at least a /29') if ipaddr.to_range.count < 16
    return if is_public
    # Check for private ranges
    case ipaddr.to_s.split('.').first.to_i
    when 10
      errors.add(:cidr, 'Must be a private IP range. 10.x networks need to be within 10.0.0.0/8.') unless IPAddr.new('10.0.0.0/8').include?(ipaddr)
    when 172
      errors.add(:cidr, 'Must be a private IP range. 172.x networks need to be within 172.16.0.0/12.') unless IPAddr.new('172.16.0.0/12').include?(ipaddr)
    when 192
      errors.add(:cidr, 'Must be a private IP range. 192.x networks need to be within 192.168.0.0/16.') unless IPAddr.new('192.168.0.0/16').include?(ipaddr)
    else
      errors.add(:cidr, 'Must be a private IP range')
    end
  rescue
    errors.add(:cidr)
  end

  def check_ip_type
    # TODO: Look at `cidr` and determine if ipv4 or not
    self.is_ipv4 = true
  end

  def format_network_name
    self.name = self.name.strip.downcase.gsub(/[^0-9A-Za-z]/, '')
  end

  # Determine if an IP is reserved.
  def restricted?(ip)
    if ip.ipv4?
      ipaddr = ip.to_s.split('.').last.to_i
      return true if ipaddr.zero? || ipaddr == 1 || ipaddr == 255
    end
    false
  end

end
