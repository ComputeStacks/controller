##
# BillingPhase
#
# If trial/discount phase is deleted, auto-transition user to final phase.
#
# Trial & Discount phases are always for new users only.
# Clock starts with the `phase_started`, viewable in the admin as `billing start`, date of the user.
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute billing_resource
#   @return [BillingResource]
#
# @!attribute phase_type
#   @return [trial,discount,final]
#
# @!attribute duration_unit
#   @return [hours,days,months,years] How long this phase will laste
#
# @!attribute duration_qty
#   @return [Integer]
#
# @!attribute new_user_only
#   @return [Boolean] Used by trial & discount phases to determine if existing users can use it.
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute updated_at
#   @return [DateTime]
#
class BillingPhase < ApplicationRecord

  include Auditable

  belongs_to :billing_resource, optional: true
  has_one :product, through: :billing_resource
  has_one :billing_plan, through: :billing_resource
  has_many :prices, class_name: 'BillingResourcePrice', foreign_key: 'billing_phase_id', dependent: :destroy
  has_many :regions, -> { distinct }, through: :prices

  validates :phase_type, inclusion: { in: %w(trial discount final), message: 'Must be one of: trial, discount, or final.' }
  validates :duration_qty, numericality: { greater_than: 0 }, if: Proc.new { |phase| phase.phase_type != 'final' && !phase.duration_qty.nil? }
  validates :duration_unit, inclusion: { in: %w(hours days months years), message: 'Must be one of: hours, days, months, or years.' }, if: Proc.new { |phase| phase.duration_qty && phase.duration_qty > 0 }

  before_destroy :migrate_subscriptions

  # @return [Array<String>]
  def available_currencies
    cur = prices.select( Arel.sql( %Q( DISTINCT(currency) ) ) )
    cur.nil? || cur.empty? ? [] : cur.map { |i| i.currency }
  end

  # @return [ActiveSupport::Duration]
  def time_unit
    return nil if duration_qty.nil? || duration_unit.nil?
    eval("#{duration_qty}.#{duration_unit}")
  end

  # Determine if obj is in this phase.
  #   - Will not validate against other phases in billing resource.
  #     - Calling method should always check 'trial' & 'discount' first.
  #   - Will always return true for 'final' phase
  #
  # @param [User] user
  def in_phase?(user)
    return true if self.phase_type == 'final'
    return true if time_unit.nil?
    return true if user.phase_started.nil?
    (Time.now - user.phase_started) <= time_unit
  end

  private

  def migrate_subscriptions
    return if self.phase_type == 'final'
    SubscriptionWorkers::PhaseAdvanceWorker.perform_async
  end

end
