# Regions
#
# provision_driver_id: Integer
# settings: Text (JSON Serialized)
# active: Boolean (Visible in order screen)
# features: {
#   'ptr' => PtrDriver # nil = not enabled
#   'container_shared_storage' => Boolean
#   'ipv6_egress' => Boolean # Enable egress-only IPv6 (NAT66) on project bridge networks
#                            # created while this is set. See #ipv6_egress.
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
#
# @!attribute network_driver
#   calico_docker, bridge
#   @return [String]
#
# @!attribute guac_url
#   Guacamole url. Should be in the form of: https://guacamole-url.com/guacamole without trailing slash.
#   @return [String]
# @!attribute guac_key_enc
#   Encrypted Guacamole authentication key. Should not be directly accessed.
#   @return [String]
# @!attribute guac_key
#   helper to read/write encrypted guac_key_enc
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
  scope :local_storage, -> { where(volume_backend: "local") }
  scope :with_clustered_storage, -> { where.not(volume_backend: "local") }

  belongs_to :location
  belongs_to :provision_driver, optional: true

  has_many :networks, dependent: :destroy

  has_and_belongs_to_many :billing_resource_prices
  has_and_belongs_to_many :user_groups

  has_many :nodes, dependent: :restrict_with_error

  has_many :container_services, class_name: "Deployment::ContainerService", dependent: :restrict_with_error
  has_many :deployments, -> { distinct }, through: :container_services
  has_many :sftp_containers, -> { distinct }, through: :deployments
  has_many :containers, through: :container_services

  has_many :volumes

  has_one :load_balancer, dependent: :destroy

  # Prometheus & Loki
  belongs_to :metric_client, optional: true
  belongs_to :log_client, optional: true

  validates :name, presence: true
  validates :volume_backend, inclusion: {in: %w[local nfs]}
  validates :fill_to, numericality: {only_integer: true, greater_than_or_equal_to: 1}
  validates :pid_limit, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :ulimit_nofile_soft, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :ulimit_nofile_hard, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :network_driver, inclusion: {in: %w[calico_docker bridge]}
  validates :p_net_size, numericality: {only_integer: true, greater_than: 23, less_than: 30} # 24-29

  serialize :settings, coder: JSON
  serialize :features, coder: JSON

  def container_count
    containers.count + sftp_containers.count
  end

  def has_clustered_storage?
    volume_driver.clustered_storage?
  end

  def has_clustered_networking?
    network_driver == "calico_docker"
  end

  ##
  # Egress-only IPv6 for tenant containers in this region.
  #
  # Stored in +features+ under the +ipv6_egress+ key -- there is no column for it.
  #
  # When set, project bridge networks *created* from this point on are built with
  # +EnableIPv6+, which has docker auto-allocate a ULA subnet and install its own NAT66
  # masquerade rule. It is egress only: nothing is published inbound over IPv6. Existing
  # networks are unaffected until they are rebuilt, and unsetting this does not remove
  # IPv6 from a network that already has it.
  #
  # Requires the node to have working upstream IPv6.
  #
  # @return [Boolean]
  def ipv6_egress
    return false unless features.is_a?(Hash)

    ActiveModel::Type::Boolean.new.cast(features["ipv6_egress"]) || false
  end
  alias_method :ipv6_egress?, :ipv6_egress

  # @param [Object] value Anything a checkbox or api client might submit ("0"/"1"/true/nil)
  # @return [Boolean]
  def ipv6_egress=(value)
    self.features = {} unless features.is_a?(Hash)

    features["ipv6_egress"] = ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def volume_driver
    case volume_backend
    when "nfs"
      DockerVolumeNfs.configure ssh_key: "#{Rails.root.join("#{ENV["CS_SSH_KEY"]}")}"
      DockerVolumeNfs
    else
      DockerVolumeLocal
    end
  end

  # @return [Boolean]
  def can_migrate_network_driver?
    return false if has_clustered_networking? # Must have clustered networking enabled by default
    return false unless nodes.count == 1 # Can't use bridged networking on clusters
    return false if networks.bridged.empty? # Must have created bridged networking
    !deployments.where(private_network: {id: nil}).includes(:private_network).empty?
  end

  ##
  # Is this user allowed to deploy to this region?
  def allow_user?(user)
    user.user_group.regions.include? self
  end

  ##
  # Guacamole

  def guac_available?
    !(guac_url.blank? || guac_key_enc.blank?)
  end

  # Encrypt the Guacamole authentication key
  def guac_key=(k)
    return nil if k.blank? # Don't save if key is blank.

    self.guac_key_enc = Secret.encrypt! k
  end

  # Decrypt the guacamole key
  def guac_key
    return nil if guac_key_enc.blank?

    Secret.decrypt! guac_key_enc
  end
  # END guacamole
  ##

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
    candidates = exclude.nil? ? nodes.available : nodes.available.where.not(id: exclude)
    return nil if candidates.empty?

    selected_node = nil
    selected_obj_count = 0
    selected_avail_cpu = 0.0
    selected_avail_memory = 0

    candidates.each do |candidate|
      # The two cheap filters run FIRST, the expensive one last. All three are
      # `next`-style rejections, so the surviving candidate set -- and therefore the
      # selection -- is identical either way; only the order of the rejected nodes'
      # add_context! payloads differs.
      #
      # It matters because nodes.available does NOT exclude under_evacuation? or
      # performing_checkup? nodes. An evacuating node never heartbeats, so it never
      # gets its capacity columns refreshed; asking can_accept_package? about it first
      # took the Prometheus fallback on every single order for the ~30 minutes until
      # under_evacuation? self-clears.
      if candidate.under_evacuation?
        add_context! "#{candidate.label}": {evacuation: true}
        next
      end
      candidate_obj_count = candidate.container_count
      if fill_to <= candidate_obj_count
        add_context! "#{candidate.label}": {filled: {max_fill: fill_to, current_qty: candidate_obj_count}}
        next
      end
      unless candidate.can_accept_package?(package)
        add_context! "#{candidate.label}": {package_unable: candidate.context}
        next
      end
      # One read, not two, and only when the ranking below can use it. Both branches of
      # that ranking check fill_by_qty (unlike Location#next_region's "full" branch, which
      # does not), so the exact predicate HERE is `!location.fill_by_qty`. We deliberately
      # gate on the coarser resource_usage_required? instead: it is true in a superset of
      # the cases, so at worst it computes an aggregate nobody reads, and one predicate
      # shared by both methods cannot drift out of step with the other.
      candidate_alloc = location.resource_usage_required? ? candidate.allocated_resources : {cpu: 0, memory: 0}
      # Unknown capacity counts as zero HERE, which ranks the node worst under every
      # "least" strategy -- the same place a failed Prometheus read used to put it.
      # This is a ranking, not a gate: can_accept_package? above already decided that
      # unknown capacity does not disqualify a node.
      current_cpu_avail = (candidate.total_cpu_cores || 0) - candidate_alloc[:cpu]
      current_mem_avail = (candidate.total_memory_mb || 0) - candidate_alloc[:memory]

      # if we have no selected candidate, start with this one
      if selected_node.nil?
        selected_node = candidate
        selected_obj_count = candidate_obj_count
        selected_avail_cpu = current_cpu_avail
        selected_avail_memory = current_mem_avail
        next
      end

      if candidate.failed_health_checks > 1
        add_context! "#{candidate.label}": {failed_health_checks: candidate.failed_health_checks}
        next
      end

      case location.fill_strategy
      when "least"

        if location.fill_by_qty
          if candidate_obj_count < selected_obj_count
            selected_node = candidate
            selected_obj_count = candidate_obj_count
            selected_avail_cpu = current_cpu_avail
            selected_avail_memory = current_mem_avail
          end
        elsif current_cpu_avail > selected_avail_cpu # by resource
          if current_mem_avail >= selected_avail_memory
            selected_node = candidate
            selected_obj_count = candidate_obj_count
            selected_avail_cpu = current_cpu_avail
            selected_avail_memory = current_mem_avail
          end
        end

      when "full"

        if location.fill_by_qty
          if candidate_obj_count > selected_obj_count
            selected_node = candidate
            selected_obj_count = candidate_obj_count
            selected_avail_cpu = current_cpu_avail
            selected_avail_memory = current_mem_avail
          end
        elsif current_cpu_avail < selected_avail_cpu # by resource
          if current_mem_avail <= selected_avail_memory
            selected_node = candidate
            selected_obj_count = candidate_obj_count
            selected_avail_cpu = current_cpu_avail
            selected_avail_memory = current_mem_avail
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
