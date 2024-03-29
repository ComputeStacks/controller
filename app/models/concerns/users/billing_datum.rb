module Users
  module BillingDatum
    extend ActiveSupport::Concern

    included do

      has_one :billing_plan, through: :user_group
      has_many :subscriptions, dependent: :destroy

      has_many :billing_events, through: :subscriptions
      has_many :billing_usages, through: :subscriptions
      has_many :products, through: :subscriptions

      before_validation :set_currency

      before_create :setup_billing

    end

    def unprocessed_usage
      billing_usages.where(processed: false).sum(:total)
    end

    # monthly run rate
    def run_rate
      subscriptions.all_active.inject(0) { |sum, item| sum += item.run_rate }
    end

    # Updated price list that only includes packages and will merge the region_id.
    def package_list
      result = { products: [] }
      Region.active.each do |i|
        p = i.user_pricing(self)
        next unless p.dig('containers', 'packages').is_a?(Array)
        p['containers']['packages'].each do |ii|
          result[:products] << ii.merge!(region: i.id)
        end
      end
      result
    end

    ##
    # =User's price list
    #
    # [+Packages+] Prices can be _per hour, month, or year_. See resources for overage pricing
    # [+Resources+] Prices are _per hour_, except for:
    #               +bandwidth+: Price is per-item (consumption)
    # [+region+] Pass a region to return _only_ a single region. This is currently only used by old API methods.
    def price_list(region = nil)
      result = {}
      if region
        result = region.user_pricing(self)
      else
        Region.active.each do |r|
          result[r.location.name] = {} if result[r.location.name].nil?
          result[r.location.name][r.name] = r.user_pricing(self)
        end
      end
      result
    end

    ##
    # Billing Usage Data

    # Aggregate total billing usage by month
    # @param [ActiveSupport::TimeWithZone] period
    def usage_by_month(period = 2.months.ago)
      q = BillingUsage.unscoped
                      .select("date_trunc('month', created_at) m, sum(total) as bill_total")
                      .where("user_id = #{id} AND created_at >= '#{period.strftime("%Y-%m-01 00:00:00")}'")
                      .group('m').order('m')
      q.map { |usage| [usage.m, usage.bill_total] }
    rescue => e
      # Temporary: Just want to see what, if any, exceptions may be generated by this sql query.
      ExceptionAlertService.new(e, 'ebef8869b1b66abc').perform
      []
    end

    # Aggregate total billing usage by day in a given month.
    #
    # @param [ActiveSupport::TimeWithZone] period
    def usage_by_date(period = Date.today)
      q = BillingUsage.unscoped
                      .select("date_trunc('day', created_at) m, sum(total) as bill_total")
                      .where("user_id = #{id} AND created_at BETWEEN '#{period.strftime("%Y-%m-01 00:00:00")}' AND '#{period.end_of_month.strftime("%Y-%m-%d 23:59:59")}'")
                      .group('m')
                      .order('m')
      q.map { |usage| [ usage.m, usage.bill_total ] }
    rescue => e
      ExceptionAlertService.new(e, '7f4e10d960cfed4e').perform
      []
    end

    # Aggregated product usage in a given month
    #
    # @param [ActiveSupport::TimeWithZone] period
    def product_usage_by_month(period = Date.today)
      q = BillingUsage.unscoped
                      .select("distinct on (products.id) products.id as pid, products.label as plabel, sum(total) as bill_total, sum(qty) as bill_qty, products.kind as pkind, products.is_aggregated as ag")
                      .where("user_id = #{id} AND billing_usages.created_at BETWEEN '#{period.strftime("%Y-%m-01 00:00:00")}' AND '#{period.end_of_month.strftime("%Y-%m-%d 23:59:59")}'")
                      .joins(:subscription_product, :product)
                      .group('products.id')
                      .order('products.id')

      q.map { |usage| { id: usage.pid, product: usage.plabel, qty: usage.bill_qty, total: usage.bill_total, kind: usage.pkind, aggregated: usage.ag } }
    rescue => e
      ExceptionAlertService.new(e, 'de4c78206506a58a').perform
      []
    end

    private

    def set_currency
      self.currency = ENV['CURRENCY'] unless BillingResourcePrice.available_currencies.include?(currency)
    end

    def setup_billing
      if self.billing_plan.nil?
        plan = BillingPlan.find_by(is_default: true)
        plan = BillingPlan.create!(name: 'default', is_default: true) if plan.nil?
        self.billing_plan = plan
      end
    end

  end
end
