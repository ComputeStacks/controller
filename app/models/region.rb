# Regions
#
# provision_driver_id: Integer
# settings: Text (JSON Serialized)
# active: Boolean (Visible in order screen)
# features: {
#   'ptr' => PtrDriver # nil = not enabled
#   'container_shared_storage' => Boolean
# }
# fill_to: For containers only, fill to this point when location fill_strategy is set to +fill+.
#
# @!attribute volume_backend
#   @return [String] One of `local` or `nfs`
# @!attribute nfs_remote_host
#   @return [String] IP Address of NFS server when connecting from the node
# @!attribute nfs_controller_ip
#   @return [String] IP Address of NFS Server when connecting from the controller
# @!attribute nfs_remote_path
#   @return [String] path to nfs volume on remote server. the volume name will be appended to this, so dont add trailing slash.
# @!attribute consul_token
#   @return [String] token used to connect to consul
#
# @!attribute network_driver
#   calico_docker, bridge
#   @return [String]
#
class Region < ApplicationRecord

  include Auditable
  include Regions::RegionMetrics
  include RegionPriceGuide
  include Regions::NfsStorage
  include Regions::VolumeStorable

  scope :sorted, -> { order "lower(name)" }
  scope :active, -> { where(active: true) }
  scope :has_nodes, -> { joins(:nodes) }
  scope :local_storage, -> { where(volume_backend: 'local') }
  scope :with_clustered_storage, -> { where.not(volume_backend: 'local') }

  belongs_to :location
  belongs_to :provision_driver, optional: true

  has_many :networks, dependent: :destroy

  has_and_belongs_to_many :billing_resource_prices
  has_and_belongs_to_many :user_groups

  has_many :nodes, dependent: :restrict_with_error
  has_many :sftp_containers, through: :nodes

  has_many :container_services, class_name: 'Deployment::ContainerService', dependent: :restrict_with_error
  has_many :deployments, -> { distinct }, through: :container_services
  has_many :sftp_containers, -> { distinct }, through: :deployments
  has_many :containers, through: :container_services

  has_many :volumes

  has_one :load_balancer, dependent: :destroy

  # Prometheus & Loki
  belongs_to :metric_client, optional: true
  belongs_to :log_client, optional: true

  validates :name, presence: true
  validates :volume_backend, inclusion: { in: %w(local nfs) }
  validates :fill_to, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :pid_limit, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ulimit_nofile_soft, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ulimit_nofile_hard, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :network_driver, inclusion: { in: %w(calico_docker bridge) }
  validates :p_net_size, numericality: { only_integer: true, greater_than: 23, less_than: 30 } # 24-29

  serialize :settings, coder: JSON
  serialize :features, coder: JSON

  def container_count
    containers.count + sftp_containers.count
  end

  def has_clustered_storage?
    volume_driver.clustered_storage?
  end

  def has_clustered_networking?
    network_driver == 'calico_docker'
  end

  def volume_driver
    case volume_backend
    when 'nfs'
      DockerVolumeNfs.configure ssh_key: "#{Rails.root}/#{ENV['CS_SSH_KEY']}"
      DockerVolumeNfs
    else
      DockerVolumeLocal
    end
  end

  def consul_config
    return {} if nodes.online.empty?

    primary_ip = nodes.online.first&.primary_ip
    dc = name.strip.downcase
    {
      http_addr: "#{CONSUL_API_PROTO}://#{primary_ip}:#{CONSUL_API_PORT}",
      dc: dc.blank? ? nil : dc,
      token: consul_token
    }
  end

  # @return [Boolean]
  def can_migrate_network_driver?
    return false if has_clustered_networking? # Must have clustered networking enabled by default
    return false unless nodes.count == 1 # Can't use bridged networking on clusters
    return false if networks.bridged.empty? # Must have created bridged networking
    !deployments.where(private_network: { id: nil }).includes(:private_network).empty?
  end

  ##
  # Is this user allowed to deploy to this region?
  def allow_user?(user)
    user.user_group.regions.include? self
  end

  ##
  # Find a node to place a given container on.
  #
  # Decision tree:
  # * Not selectable if qty is over max fill, regardless of fill_by_qty
  # * Not selectable if there is physically not enough resources on the node
  # * Not selectable if the node is under evacuation
  # * Least Filled, qty based
  #   * the node with the fewest number of containers is chosen.
  # * Least filled, resource based
  #   * First prioritizes the node if it has both more memory, and cpu
  #   * Second, if this node has more available memory than the previous node, and
  #     it has enough cpu for the request package, then still choose this node.
  # * Fill each node, qty based
  #   * Select node if it has the most containers (node would not even gotten
  #     here if it was at max_fill)
  # * Fill each node, resource based
  #   * First prioritize if both cpu and memory available is less than the previous
  #   * Second, choose node if memory available is less than previous node, and cpu
  #     avail is still enough for the package.
  #
  # @param package [BillingPackage]
  def find_node(package, exclude = nil)
    candidates = exclude.nil? ? nodes.available : nodes.available.where("id != ?", exclude)
    return nil if candidates.empty?

    selected_node = nil
    selected_obj_count = 0
    selected_avail_cpu = 0.0
    selected_avail_memory = 0

    candidates.each do |candidate|
      unless candidate.can_accept_package?(package)
        add_context! "#{candidate.label}": { package_unable: candidate.context }
        next
      end
      if candidate.under_evacuation?
        add_context! "#{candidate.label}": { evacuation: true }
        next
      end
      candidate_obj_count = candidate.container_count
      if fill_to <= candidate_obj_count
        add_context! "#{candidate.label}": { filled: { max_fill: fill_to, current_qty: candidate_obj_count } }
        next
      end
      current_cpu_avail = candidate.metric_cpu_cores[:cpu] - candidate.allocated_resources[:cpu]
      current_mem_avail = candidate.metric_memory(:MB)[:memory] - candidate.allocated_resources[:memory]

      # if we have no selected candidate, start with this one
      if selected_node.nil?
        selected_node = candidate
        selected_obj_count = candidate_obj_count
        selected_avail_cpu = current_cpu_avail
        selected_avail_memory = current_mem_avail
        next
      end

      if candidate.failed_health_checks > 1
        add_context! "#{candidate.label}": { failed_health_checks: candidate.failed_health_checks }
        next
      end

      case location.fill_strategy
      when 'least'

        if location.fill_by_qty
          if candidate_obj_count < selected_obj_count
            selected_node = candidate
            selected_obj_count = candidate_obj_count
            selected_avail_cpu = current_cpu_avail
            selected_avail_memory = current_mem_avail
          end
        else # by resource
          if current_cpu_avail > selected_avail_cpu
            if current_mem_avail >= selected_avail_memory
              selected_node = candidate
              selected_obj_count = candidate_obj_count
              selected_avail_cpu = current_cpu_avail
              selected_avail_memory = current_mem_avail
            end
          end
        end

      when 'full'

        if location.fill_by_qty
          if candidate_obj_count > selected_obj_count
            selected_node = candidate
            selected_obj_count = candidate_obj_count
            selected_avail_cpu = current_cpu_avail
            selected_avail_memory = current_mem_avail
          end
        else # by resource
          if current_cpu_avail < selected_avail_cpu
            if current_mem_avail <= selected_avail_memory
              selected_node = candidate
              selected_obj_count = candidate_obj_count
              selected_avail_cpu = current_cpu_avail
              selected_avail_memory = current_mem_avail
            end
          end
        end

      else
        next
      end
    end
    selected_node
  end

  def loki_container_endpoint
    return nil if log_client.nil? || loki_endpoint.blank?
    return loki_endpoint if log_client.username.blank? || log_client.password.blank?
    uri = loki_endpoint.split("://")
    return nil if uri.count == 1 # missing protocol!
    "#{uri[0]}://#{log_client.username}:#{log_client.password}@#{uri[1]}"
  end

end
