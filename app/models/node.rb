#
# primary_ipv6
# primary_ip
# agent_host  # optional cs-agent address; blank falls back to primary_ip (see #agent_address)
# private_ip
# cluster_interface default=eth0
# job_status:string %w(idle evacuating recovering) # Used to track jobs performed on this host.
#
class Node < ApplicationRecord
  include Auditable
  include Nodes::ConsulNode
  include Nodes::MaintenanceNode
  include Nodes::NodeMetrics

  scope :sorted, -> { order(Arel.sql("lower(label), lower(hostname)")) }

  # Able to connect, and existing deployments can use it.
  scope :online, -> { where(disconnected: false, maintenance: false) }
  scope :offline, -> { where(Arel.sql("disconnected = true OR maintenance = true")) }

  # Available for new orders
  scope :available, -> { where(active: true, disconnected: false, maintenance: false) }

  belongs_to :region
  has_one :location, through: :region
  has_many :containers, class_name: "Deployment::Container", dependent: :restrict_with_error
  has_many :deployments, through: :containers
  has_and_belongs_to_many :event_logs
  has_many :container_services, through: :containers, source: :service
  # has_many :ingress_rules, through: :container_services # doesnt include sftp!
  has_many :sftp_containers, class_name: "Deployment::Sftp", dependent: :destroy

  has_one :metric_client, through: :region

  has_and_belongs_to_many :volumes

  has_many :alert_notifications, dependent: :destroy

  validates :label, presence: true
  validates :hostname, presence: true

  validates :primary_ip, format: {with: /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/}
  validates :public_ip, format: {with: /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/}

  # RFC-1123 hostname, which a dotted-quad IPv4 literal also satisfies — so this accepts
  # both a raw address (100.64.79.114) and a DNS name (node1.tailnet.ts.net). Deliberately
  # NOT the IPv4-only regex above: pinning a name survives the address being reassigned.
  # IPv6 is rejected because #agent_address is interpolated into a URL unbracketed.
  validates :agent_host,
    format: {with: /\A[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?)*\z/i},
    allow_blank: true

  # validates :port_begin, inclusion: { in: 7000..51000 }
  # validates :port_end, inclusion: { in: 7000..51000 }

  validate :valid_volume_path
  validates :block_write_bps, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :block_read_bps, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :block_write_iops, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :block_read_iops, numericality: {only_integer: true, greater_than_or_equal_to: 0}

  after_create_commit :sync_volumes

  # Store an unset override as NULL, not "". The admin form always submits a string, and a
  # blank one must not look like a configured address to anything that inspects the column.
  before_validation :normalize_agent_host

  # Mint the per-node admin Bearer the controller uses for privileged cs-agent
  # calls. before_save (not after_create_commit) so the token is present the
  # moment the row exists and on any insert path that skips commit callbacks.
  before_save :mint_agent_token, if: -> { agent_token_encrypted.blank? }

  def container_count
    containers.count + sftp_containers.count
  end

  # Plaintext per-node admin Bearer (decrypted). Sent by Agent::Client; never
  # leaves the controller otherwise. nil if unset or undecryptable.
  def agent_token
    return nil if agent_token_encrypted.blank?
    Secret.decrypt!(agent_token_encrypted)
  end

  def agent_token=(data)
    self.agent_token_encrypted = data.blank? ? nil : Secret.encrypt!(data)
  end

  # sha256 of the admin token — the only form ever exposed (to the provisioner,
  # which installs it as the agent's `admin.token_hash`). Not a usable Bearer.
  # Guarded: Secret.decrypt! returns nil on failure and hexdigest(nil) raises.
  def agent_token_hash
    t = agent_token
    t.blank? ? nil : Digest::SHA256.hexdigest(t)
  end

  def self.system_containers
    %w[
      alertmanager
      cadvisor
      calico-node
      cs-agent
      grafana
      loki
      prometheus
      vault-bootstrap
    ]
  end

  def ingress_rules
    container_services.map(&:ingress_rules) + sftp_containers.map(&:ingress_rules)
  end

  # @return [Hash]
  def container_io_limits
    return {} if volume_device.blank?
    return {} if block_write_bps.zero? && block_read_bps.zero?

    h = {}
    unless block_write_bps.zero?
      h["BlkioDeviceWriteBps"] = [
        {
          "Path" => volume_device,
          "Rate" => block_write_bps
        }
      ]
    end
    unless block_read_bps.zero?
      h["BlkioDeviceReadBps"] = [
        {
          "Path" => volume_device,
          "Rate" => block_read_bps
        }
      ]
    end
    unless block_write_iops.zero?
      h["BlkioDeviceWriteIOps"] = [
        {
          "Path" => volume_device,
          "Rate" => block_write_iops
        }
      ]
    end
    unless block_read_iops.zero?
      h["BlkioDeviceReadIOps"] = [
        {
          "Path" => volume_device,
          "Rate" => block_read_iops
        }
      ]
    end
    h["OomKillDisable"] = true if region.disable_oom
    h["PidsLimit"] = region.pid_limit unless region.pid_limit.zero?
    unless region.ulimit_nofile_soft.zero? || region.ulimit_nofile_hard.zero?
      h["Ulimits"] = [
        {
          "Name" => "nofile",
          "Soft" => region.ulimit_nofile_soft,
          "Hard" => region.ulimit_nofile_hard
        }
      ]
    end
    h
  end

  ##
  # Address the controller dials for this node's cs-agent (see Agent::Client). Separate from
  # primary_ip because the agent channel is plain HTTP and can be moved onto an encrypted
  # path (Tailscale) on its own; primary_ip stays the Docker/SSH address, the HAProxy backend
  # address, and the metadata.internal target baked into every container's ExtraHosts.
  #
  # Blank falls back to primary_ip, so a node that has never been configured behaves exactly
  # as it did before the column existed — and blanking the column is a complete rollback.
  #
  # NB: the agent serves admin and customer-metadata traffic from ONE listener. Containers
  # reach it at primary_ip:8500, so the agent must keep listening there regardless of what
  # this is set to; narrowing its listen_addr to the override would break every container.
  #
  # @return [String]
  def agent_address
    agent_host.presence || primary_ip
  end

  ##
  # Clients
  def client(timeout = 1)
    # dup: Docker.connection.options is memoised process-wide and Docker::Connection
    # stores the hash by reference, so mutating it in place let concurrent Sidekiq
    # threads overwrite each other's timeouts -- a 5s heartbeat and a 180s image pull
    # fought, and either could win for both.
    opts = Docker.connection.options.dup
    opts[:connect_timeout] = 15 * timeout
    opts[:read_timeout] = 60 * timeout
    opts[:write_timeout] = 60 * timeout
    Docker::Connection.new("tcp://#{primary_ip}:2376", opts)
  end

  def docker_major_version
    client.version["Version"].split(".")[0].to_i
  rescue
    nil
  end

  def fast_client
    opts = Docker.connection.options.dup # see #client -- the shared hash is mutated in place
    opts[:connect_timeout] = 5
    opts[:read_timeout] = 5
    opts[:write_timeout] = 5
    Docker::Connection.new("tcp://#{primary_ip}:2376", opts)
  end

  def host_client
    DockerSSH::Node.new("ssh://#{primary_ip}:#{ssh_port}", {key: Rails.root.join(ENV["CS_SSH_KEY"].to_s).to_s})
  end

  def list_all_containers
    Docker::Container.all({all: true}, client)
  rescue
    []
  end

  def iptable_rules
    q = "external_access = true AND port_nat > 0 AND (proto = 'udp' OR (proto = 'tcp' AND tcp_lb = false))"
    (container_services.map { |i| i.ingress_rules.where(Arel.sql(q)) } + sftp_containers.map { |i| i.ingress_rules.where(Arel.sql(q)) }).flatten
  end

  private

  def normalize_agent_host
    # Strip before testing for blank so a pasted address with surrounding whitespace is
    # cleaned rather than failing the format validation.
    self.agent_host = agent_host&.strip&.presence
  end

  def mint_agent_token
    self.agent_token = SecureRandom.urlsafe_base64(32)
  end

  ##
  # When using clustered storage, we need to ensure that our volumes exist for faster fail over.
  def sync_volumes
    return true unless region.has_clustered_storage?

    region.volumes.active.each do |vol|
      unless vol.nodes.include? self
        vol.nodes << self
        VolumeWorkers::ProvisionVolumeWorker.perform_async vol.global_id
      end
    end
  end

  def valid_volume_path
    return if volume_device.blank?

    if volume_device.count("/").zero?
      errors.add(:volume_device, "is not a valid path")
    end
  end
end
