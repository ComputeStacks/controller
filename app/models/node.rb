#
# primary_ipv6
# primary_ip
# private_ip
# cluster_interface default=eth0
# job_status:string %w(idle evacuating recovering) # Used to track jobs performed on this host.
#
class
Node < ApplicationRecord

  include Auditable
  include Nodes::ConsulNode
  include Nodes::MaintenanceNode
  include Nodes::NodeMetrics

  scope :sorted, -> { order( Arel.sql("lower(label), lower(hostname)") ) }

  # Able to connect, and existing deployments can use it.
  scope :online, -> { where(disconnected: false, maintenance: false) }
  scope :offline, -> { where( Arel.sql( %q(disconnected = true OR maintenance = true) ) ) }

  # Available for new orders
  scope :available, -> { where(active: true, disconnected: false, maintenance: false) }

  belongs_to :region
  has_one :location, through: :region
  has_many :containers, class_name: 'Deployment::Container', dependent: :restrict_with_error
  has_many :deployments, through: :containers
  has_and_belongs_to_many :event_logs
  has_many :container_services, through: :containers, source: :service
  # has_many :ingress_rules, through: :container_services # doesnt include sftp!
  has_many :sftp_containers, class_name: 'Deployment::Sftp', dependent: :destroy

  has_one :metric_client, through: :region

  has_and_belongs_to_many :volumes

  has_many :alert_notifications, dependent: :destroy

  validates :label, presence: true
  validates :hostname, presence: true

  validates :primary_ip, format: { with: /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/ }
  validates :public_ip, format: { with: /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/ }

  # validates :port_begin, inclusion: { in: 7000..51000 }
  # validates :port_end, inclusion: { in: 7000..51000 }

  validate :valid_volume_path
  validates :block_write_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :block_read_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :block_write_iops, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :block_read_iops, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  after_create_commit :sync_volumes

  def container_count
    containers.count + sftp_containers.count
  end

  def self.system_containers
    %w(
      alertmanager
      cadvisor
      calico-node
      cs-agent
      grafana
      loki
      prometheus
      vault-bootstrap
    )
  end

  def ingress_rules
    container_services.map { |i| i.ingress_rules } + sftp_containers.map { |i| i.ingress_rules }
  end

  # @return [Hash]
  def container_io_limits
    return {} if volume_device.blank?
    return {} if (block_write_bps.zero? && block_read_bps.zero?)
    h = {}
    h['BlkioDeviceWriteBps'] = [
      {
        'Path' => volume_device,
        'Rate' => block_write_bps
      }
    ] unless block_write_bps.zero?
    h['BlkioDeviceReadBps'] = [
      {
        'Path' => volume_device,
        'Rate' => block_read_bps
      }
    ] unless block_read_bps.zero?
    h['BlkioDeviceWriteIOps'] = [
      {
        'Path' => volume_device,
        'Rate' => block_write_iops
      }
    ] unless block_write_iops.zero?
    h['BlkioDeviceReadIOps'] = [
      {
        'Path' => volume_device,
        'Rate' => block_read_iops
      }
    ] unless block_read_iops.zero?
    h['OomKillDisable'] = true if region.disable_oom
    h['PidsLimit'] = region.pid_limit unless region.pid_limit.zero?
    h['Ulimits'] = [
      {
        'Name' => 'nofile',
        'Soft' => region.ulimit_nofile_soft,
        'Hard' => region.ulimit_nofile_hard
      }
    ] unless region.ulimit_nofile_soft.zero? || region.ulimit_nofile_hard.zero?
    h
  end

  ##
  # Clients
  def client(timeout = 1)
    opts = Docker.connection.options
    opts[:connect_timeout] = 15 * timeout
    opts[:read_timeout] = 60 * timeout
    opts[:write_timeout] = 60 * timeout
    Docker::Connection.new("tcp://#{self.primary_ip}:2376", opts)
  end

  def fast_client
    opts = Docker.connection.options
    opts[:connect_timeout] = 5
    opts[:read_timeout] = 5
    opts[:write_timeout] = 5
    Docker::Connection.new("tcp://#{self.primary_ip}:2376", opts)
  end

  def host_client
    DockerSSH::Node.new("ssh://#{self.primary_ip}:#{ssh_port}", {key: ENV['CS_SSH_KEY']})
  end

  def list_all_containers
    Docker::Container.all({all: true}, client)
  rescue
    []
  end

  def iptable_rules
    return [] if region.public_network?
    q = "external_access = true AND port_nat > 0 AND (proto = 'udp' OR (proto = 'tcp' AND tcp_lb = false))"
    (container_services.map { |i| i.ingress_rules.where( Arel.sql q ) } + sftp_containers.map { |i| i.ingress_rules.where( Arel.sql q ) }).flatten
  end

  private

  ##
  # When using clustered storage, we need to ensure that our volumes exist for faster fail over.
  def sync_volumes
    return true unless region.has_clustered_storage?
    region.volumes.active.each do |vol|
      unless vol.nodes.include? self
        vol.nodes << self
        VolumeWorkers::ProvisionVolumeWorker.perform_async vol.to_global_id.to_s
      end
    end
  end

  def valid_volume_path
    return if volume_device.blank?
    if volume_device.count('/').zero?
      errors.add(:volume_device, 'is not a valid path')
    end
  end

end
