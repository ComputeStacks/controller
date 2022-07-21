##
# Order
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute status
#   @return [open,pending,awaiting_payment,processing,cancelled,failed,completed]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute user
#   @return [User]
#
# @!attribute location
#   @return [Location]
#
# @!attribute audits
#   @return [Array<Audit>]
#
# @!attribute events
#   @return [Array<EventLog>]
#
#
class Order < ApplicationRecord

  include Auditable
  include Orders::AppEvent
  include Orders::StateManager
  include UrlPathFinder

  default_scope { order(created_at: :desc) }

  scope :sorted, -> { order(created_at: :desc) }

  belongs_to :user, optional: true
  belongs_to :deployment, optional: true
  belongs_to :location, optional: true

  has_many :audits, -> { where rel_model: 'Order' }, foreign_key: 'rel_uuid'
  has_many :events, -> { distinct }, through: :audits, source: :event_logs

  after_create :generate_details

  serialize :order_data, JSON

  def data
    return {} if order_data.nil?
    order_data.with_indifferent_access
  end

  def data=(params)
    self.order_data = params
  end

  def requires_project?
    data[:raw_order].each do |i|
      return true if i[:product_type] == 'container'
    end
    false
  end

  def order_type
    product_type = nil
    data[:raw_order].each do |i|
      if %w(container).include?(i[:product_type])
        product_type = i[:product_type]
        break
      end
    end
    product_type
  rescue
    nil
  end

  def currency_symbol
    return nil if user.nil?
    Monetize.parse(user.currency)&.currency&.html_entity
  end

  def self.clean!
    Order.where(Arel.sql(%Q(status = 'open' and created_at < '#{1.week.ago.iso8601}'))).delete_all
    Order.where(Arel.sql(%Q(status = 'awaiting_payment' and created_at < '#{1.week.ago.iso8601}'))).update_all status: 'cancelled'
  end

  private

  # Generate details that can be used for order confirmation
  def generate_details
    new_order = order_data
    return true if new_order.empty? # Do nothing.
    raw_order = new_order['raw_order']
    new_order['summary'] = []
    if raw_order.nil? || !raw_order.kind_of?(Array)
      errors.add(:base, "Order Data is in an invalid format.")
      return false
    end
    # Setup for Deployment
    unless new_order['deployment'].nil?

      # Link this order to the deployment
      if new_order['deployment']['id'] && self.deployment.nil?
        deployment = Deployment.find_for(user, token: new_order['deployment']['id'])
        update(deployment: deployment) if deployment
      end

    end
    # Calculate totals.
    hourly = 0.0
    monthly = 0.0
    new_order['summary'].each do |i|
      if i[:total]
        if i[:term] == 'hourly'
          hourly += i[:total].to_f
          monthly += (i[:total].to_f * 24) * 30
        elsif i[:term] == 'monthly'
          hourly += ((i[:total].to_f * 12) / 365) / 24
          monthly += i[:total].to_f
        end
      end
    end
    new_order['total'] = {
      recurring: {
        hourly: "#{currency_symbol}#{sprintf('%0.4f', hourly)}",
        monthly: "#{currency_symbol}#{sprintf('%0.2f', monthly)}"
      }
    }
    # tax_rate = self.user.tax_rate
    # unless tax_rate == 0
    #   new_order['total'][:recurring][:tax] = "#{currency_symbol}#{sprintf('%0.2f', monthly * (self.user.tax_rate / 100))}"
    # end
    if new_order['location_id'] && location.nil?
      loc = Location.find_by(id: new_order['location_id'])
      update(location: loc) if loc
    end
    update order_data: new_order
  end

end
