##
# User Group
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute active
#   @return [Boolean]
#
# @!attribute billing_plan
#   @return [BillingPlan]
#
# @!attribute is_default
#   @return [Boolean]
#
# @!attribute name
#   @return [String]
#
# @!attribute q_containers
#   How many containers a user can deploy. [default: 250]
#   @return [Integer]
#
# @!attribute q_cr
#   How many container registries. [default: 20]
#   @return [Integer]
#
# @!attribute q_dns_zones
#   @return [Integer]
#
# @!attribute allow_local_volume
#   When using clustered storage, enabling this will allow users to manually specify a volume should run locally.
#   @return [Boolean]
#
# @!attribute bill_offline
#   Continue billing package when container is stopped? (default: true)
#   @return [Boolean]
#
# @!attribute bill_suspend
#   Continue billing when a user is suspended? (default: true)
#   @return [Boolean]
#
# @!attribute remove_stopped
#   Delete stopped containers from the node? (default: false)
#   @return [Boolean]
#
class UserGroup < ApplicationRecord

  include Auditable

  scope :sorted, -> { order( Arel.sql("lower(name)") ) }

  has_many :users, dependent: :restrict_with_error
  has_and_belongs_to_many :regions
  has_many :locations, through: :regions

  belongs_to :billing_plan

  validates :name, length: { in: 2..50 }
  validates :q_containers, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2147483647 }
  validates :q_dns_zones, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2147483647 }
  validates :q_cr, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2147483647 }

  before_destroy :ensure_new_default, prepend: true
  after_commit :update_default
  after_commit :ensure_active_default

  def current_quota(user, refresh_cache = false)
    Rails.cache.delete("user_#{user.id}_quota") if refresh_cache
    Rails.cache.fetch("user_#{user.id}_quota", expires_in: 4.hours) do
      {
        containers: {
          current: user.deployed_containers.count,
          quota: q_containers,
          is_over: user.deployed_containers.count >= q_containers,
          available: q_containers - user.deployed_containers.count
        },
        cr: {
          current: user.container_registries.count,
          quota: q_cr,
          is_over: user.container_registries.count >= q_cr,
          available: q_cr - user.container_registries.count
        },
        dns_zones: {
          current: user.dns_zones.count,
          quota: q_dns_zones,
          is_over: user.dns_zones.count >= q_dns_zones,
          available: q_dns_zones - user.dns_zones.count
        }
      }
    end
  end

  def available_regions(location = nil)
    location ? regions.where(location: location) : regions
  end

  private

  # :doc:
  # Force active if we're set to default.
  def ensure_active_default
    self.update_column active, true if self.is_default && !self.active
  end

  # :doc:
  # Ensure we choose another default if this +is_default+ :doc:
  def update_default
    UserGroup.where("id != ?", self.id).update_all(is_default: false) if self.is_default
  end

  # :doc:
  # Before deleting, migrate +is_default+ to another +active+ UserGroup.
  # If there are no other locations, abort this deletion.
  def ensure_new_default
    return true unless self.is_default
    if UserGroup.active.count < 2
      throw(:abort)
    else
      unless UserGroup.active.where.not(id: self.id).first.update_attribute(:is_default, true)
        throw(:abort) # Prevent destruction if this fails.
      end
    end
  end

end
