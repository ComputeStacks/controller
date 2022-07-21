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

  scope :sorted, -> { order(Arel.sql("lower(name) ASC")) }

  has_many :regions, dependent: :restrict_with_error
  has_many :user_groups, -> { distinct }, through: :regions
  has_many :provision_drivers, -> { distinct }, through: :regions

  has_many :nodes, -> { distinct }, through: :regions
  has_many :networks, -> { distinct }, through: :regions
  has_many :container_services, -> { distinct }, through: :regions
  has_many :containers, through: :container_services
  has_many :deployments, through: :regions
  has_many :sftp_containers, -> { distinct }, through: :deployments

  validates :name, length: { in: 2..50 }

  def allocated_resources
    total_cpu = containers.sum(:cpu) + (sftp_containers.count / 2.0) # 1/2 core per sftp container
    total_memory = containers.sum(:memory) + (sftp_containers.count * 512) # 512MB per sftp containers
    h = {
      total: {
        containers: containers.count,
        sftp_containers: sftp_containers.count,
        cpu: total_cpu,
        memory: total_memory
      },
      availability_zones: []
    }

    regions.each do |r|
      r_cpu = r.containers.sum(:cpu) + (r.sftp_containers.count / 2.0) # 1/2 core per sftp container
      r_memory = r.containers.sum(:memory) + (r.sftp_containers.count * 512) # 512MB per sftp containers
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
          sftp_containers: r.sftp_containers.count,
          cpu: r_cpu,
          memory: r_memory
        },
        projects: p
      }
    end
    h
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

    packages = [ BillingPackage.new(cpu: 1, memory: 512) ] if packages.empty?

    selected_region = nil
    selected_obj_count = 0
    selected_alloc = { cpu: { used: 0, available: 0, usage: 100 }, memory: { used: 0, available: 0, usage: 100 } }

    candidates.each do |candidate|
      next if candidate.nodes.online.empty?
      candidate_obj_count = candidate.container_count
      next if candidate.fill_to <= (candidate_obj_count + qty) # Don't choose regions that are over capacity!
      current_alloc = candidate.current_allocated_usage
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
      when 'least'
        if fill_by_qty
          # Choose current candidate if it has less containers
          if candidate_obj_count < selected_obj_count
            selected_region = candidate
            selected_obj_count = candidate_obj_count
            selected_alloc = current_alloc
          end
        else # by resources
          # Require both cpu and memory to be greater
          if current_alloc[:cpu][:usage] < selected_alloc[:cpu][:usage]
            if current_alloc[:memory][:usage] <= selected_alloc[:memory][:usage]
              selected_region = candidate
              selected_obj_count = candidate_obj_count
              selected_alloc = current_alloc
            end
          end
        end
      when 'full'
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
    if resource == 'container'
      Location.where("user_groups.id = ?", user.user_group.id).joins(:user_groups).distinct
    else
      []
    end
  end

  def self.find_for_user(id, user)
    user.user_group.locations.find_by(id: id)
  end

end
