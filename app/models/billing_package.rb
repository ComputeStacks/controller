##
# BillingPackage
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute cpu
#   @return [Decimal] Support for fractional cpu cores.
#
# @!attribute memory
#   @return [Integer] In MB
#
# @!attribute storage
#   @return [Integer] In GB
#
# @!attribute bandwidth
#   @return [Integer] In GB
#
# @!attribute backup
#   @return [Integer] In GB
#
# @!attribute local_disk
#   @return [Integer] In GB -- local in-container storage, not inside of a volume.
#
# @!attribute memory_swap
#   @return [Integer]
#
# @!attribute memory_swappiness
#   @return [Integer]
#
class BillingPackage < ApplicationRecord

  include Auditable

  belongs_to :product
  has_many :billing_plans, through: :product

  validates :backup, numericality: { greater_than_or_equal_to: 0 }
  validates :bandwidth, numericality: { greater_than_or_equal_to: 0 }
  validates :cpu, numericality: { greater_than: 0 }
  validates :memory, numericality: { greater_than_or_equal_to: 256 }
  validate :memory_unit_validation
  validates :local_disk, numericality: { greater_than_or_equal_to: 0 }
  validates :memory_swappiness, numericality: { only_integer: true, less_than_or_equal_to: 100, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :memory_swap, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :storage, numericality: { greater_than_or_equal_to: 0 }

  before_validation :make_swap_nil

  before_save :check_resources

  ##
  # Filter available packages
  #
  # limits
  #     {
  #       'cpu' => 0.0,
  #       'memory' => 0
  #     }
  #
  def self.find_by_plan(billing_plan, limits = nil)
    packages = if limits
                 BillingPackage.where("(cpu >= ? AND memory >= ?) AND products.kind = 'package'", limits[:cpu], limits[:memory]).joins(:product).order(:memory)
               else
                 BillingPackage.where(products: { kind: 'package' }).joins(:product).order(:memory)
               end
    available_packages = []
    packages.each do |i|
      available_packages << i if i.product.billing_resources.where(billing_plan: billing_plan).exists?
    end
    available_packages
  end

  private

  ## Validate Memory
  # Must be in units of 256 MB
  def memory_unit_validation
    unless memory.blank?
      unless memory % 256 == 0
        errors.add(:memory, "must be in units of 256 MB")
      end
    end
  end

  def check_resources
    # Make sure Storage and Bandwidth are set to nil if they have an empty string.
    self.storage = nil if self.storage.blank? || self.storage.zero?
    self.bandwidth = nil if self.bandwidth.blank? || self.bandwidth.zero?
  end

  def make_swap_nil
    self.memory_swappiness = nil if memory_swappiness.blank?
    self.memory_swap = nil if memory_swap.to_i.zero?
  end


end
