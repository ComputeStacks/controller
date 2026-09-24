##
# Location
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute regions
#   @return [Array<Region>]
#
# @!attribute fill_strategy
#   @return [least,full]
#
# @!attribute fill_by_qty
#   True (default) will fill based on number of containers. False will look at cpu and memory allocations to determine least filled node.
#   @return [Boolean]
#
# @!attribute overcommit_cpu
#   @return [Boolean]
#
# @!attribute overcommit_memory
#   @return [Boolean]
#
# @!attribute nodes
#   @return [Array<Nodes>]
#
# @!attribute user_groups
#   @return [Array<UserGroup>]
#
# @!attribute networks
#   @return [Array<Network>]
#
# @!attribute container_services
#   @return [Array<Deployment::ContainerService>]
#
# @!attribute containers
#   @return [Array<Deployment::Container>]
#
# @!attribute deployments
#   @return [Array<Deployment>]
#
# @!attribute sftp_containers
#   @return [Array<Deployment::Sftp>]
#
class Location < ApplicationRecord
  # fill_strategory:
  #  - least: Fill each region evenly.
  #  - full: Fill until the regions +fill_to+ variable.
  #

  include Auditable

  scope :active, -> { where(active: true) }

  scope :sorted, -> { order "lower(name)" }

  has_many :regions, dependent: :restrict_with_error
  has_many :user_groups, -> { distinct }, through: :regions
  has_many :provision_drivers, -> { distinct }, through: :regions

  has_many :nodes, -> { distinct }, through: :regions
  has_many :networks, -> { distinct }, through: :regions
  has_many :container_services, -> { distinct }, through: :regions
  has_many :containers, through: :container_services
  has_many :deployments, through: :regions
  has_many :sftp_containers, -> { distinct }, through: :deployments

  validates :name, length: {in: 2..50}

  def allocated_resources
    # Deployment::Sftp::ALLOCATED_* rather than the 0.5 core / 512 MB this used to assume:
    # the node enforces 1 core / 1024 MB for an sftp container, so this under-reported both
    # by half. Same figures the placement gates now use.
    # SFTP rows are reached by NODE here, not through the deployments association, so this
    # agrees with Region#current_allocated_usage and so the zone rows below sum to this
    # total. A project with services in two zones appears in both zones' `deployments`,
    # which would attribute its sftp container to both; the node it runs on is whose
    # capacity it actually consumes.
    location_sftp = Deployment::Sftp.where(node_id: nodes.select(:id))
    sftp_alloc = Deployment::Sftp.allocated_resources(location_sftp)
    total_cpu = containers.sum(:cpu) + sftp_alloc[:cpu]
    total_memory = containers.sum(:memory) + sftp_alloc[:memory]
    h = {
      total: {
        containers: containers.count,
        sftp_containers: location_sftp.active.count,
        cpu: total_cpu,
        memory: total_memory
      },
      availability_zones: []
    }

    regions.each do |r|
      r_sftp = Deployment::Sftp.where(node_id: r.nodes.select(:id))
      r_sftp_alloc = Deployment::Sftp.allocated_resources(r_sftp)
      r_cpu = r.containers.sum(:cpu) + r_sftp_alloc[:cpu]
      r_memory = r.containers.sum(:memory) + r_sftp_alloc[:memory]
      p = []
      r.deployments.each do |d|
        p << {
          id: d.id,
          name: d.name
        }
      end
      h[:availability_zones] << {
        id: r.id,
        name: r.name,
        allocated: {
          containers: r.containers.count,
          sftp_containers: r_sftp.active.count,
          cpu: r_cpu,
          memory: r_memory
        },
        projects: p
      }
    end
    h
  end

  # Shape of #current_allocated_usage, used in place of it when no branch of
  # #next_region can read the result. See #resource_usage_required?.
  NO_ALLOCATION = {
    cpu: {used: 0, available: 0, usage: 100},
    memory: {used: 0, available: 0, usage: 100}
  }.freeze

  ##
  # Do #next_region and Region#find_node actually consume the allocation figure?
  #
  # Both callers gate on this, so a change made for one moves node placement as well as
  # zone placement. Keep it describing the CONFIGURATION, not either call site.
  #
  # That call costs a query plus TWO Prometheus reads per node, and against a zone on
  # another continent a read is ~0.6s -- so it is the most expensive thing in the order
  # path. Under a common configuration nothing reads its result at all:
  #
  # * both overcommit flags on  -> neither capacity gate runs
  # * "least" + fill_by_qty     -> zones are ranked by container count, not resources
  #
  # "full" always ranks by resources, and "least" without fill_by_qty ranks by cpu/memory
  # usage, so both still need it.
  #
  # This changes no placement decision -- it only skips computing a number that would be
  # discarded. RegionsTest / LocationTest lock that down.
  #
  # @return [Boolean]
  def resource_usage_required?
    return true unless overcommit_cpu && overcommit_memory
    return true unless fill_strategy == "least"
    !fill_by_qty
  end

  # Find the the next available region given the current fill strategy.
  #
  # resource:
  #  - container
  # @param packages [Array<BillingPackage>]
  # @param user [User]
  def next_region(packages, user, qty = 1)
    candidates = regions.active.has_nodes.where("user_groups.id = ?", user.user_group.id).joins(:user_groups).order(fill_to: :desc).distinct
    return nil if candidates.empty?

    packages = [BillingPackage.new(cpu: 1, memory: 512)] if packages.empty?

    selected_region = nil
    selected_obj_count = 0
    selected_alloc = NO_ALLOCATION

    candidates.each do |candidate|
      next if candidate.nodes.online.empty?
      candidate_obj_count = candidate.container_count
      next if candidate.fill_to <= (candidate_obj_count + qty) # Don't choose regions that are over capacity!
      current_alloc = resource_usage_required? ? candidate.current_allocated_usage : NO_ALLOCATION
      req_cpu = packages.sum { |p| p.cpu }
      req_mem = packages.sum { |p| p.memory }

      unless overcommit_cpu
        next unless current_alloc[:cpu][:available] >= req_cpu
        next if (req_cpu + current_alloc[:cpu][:used]) > current_alloc[:cpu][:available]
      end

      unless overcommit_memory
        next unless current_alloc[:memory][:available] > req_mem
        next if (req_mem + current_alloc[:memory][:used]) > current_alloc[:memory][:available]
      end

      # If n has not be chosen and we got this far,
      # immediately select this node.
      if selected_region.nil?
        selected_region = candidate
        selected_obj_count = candidate_obj_count
        selected_alloc = current_alloc
        next
      end

      case fill_strategy
      when "least"
        if fill_by_qty
          # Choose current candidate if it has less containers
          if candidate_obj_count < selected_obj_count
            selected_region = candidate
            selected_obj_count = candidate_obj_count
            selected_alloc = current_alloc
          end
        elsif current_alloc[:cpu][:usage] < selected_alloc[:cpu][:usage] # by resources
          # Require both cpu and memory to be greater
          if current_alloc[:memory][:usage] <= selected_alloc[:memory][:usage]
            selected_region = candidate
            selected_obj_count = candidate_obj_count
            selected_alloc = current_alloc
          end
        end
      when "full"
        # Require both cpu and memory to be less
        if current_alloc[:cpu][:usage] > selected_alloc[:cpu][:usage]
          if current_alloc[:memory][:usage] >= selected_alloc[:memory][:usage]
            selected_region = candidate
            selected_obj_count = candidate_obj_count
            selected_alloc = current_alloc
          end
        end
      else
        next
      end
    end
    selected_region
  end

  # Find Available Locations for a given User Resource pair.
  def self.available_for(user, resource)
    if resource == "container"
      Location.where("user_groups.id = ?", user.user_group.id).joins(:user_groups).distinct
    else
      []
    end
  end

  def self.find_for_user(id, user)
    user.user_group.locations.find_by(id: id)
  end
end
