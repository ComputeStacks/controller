module ContainerServices
  module ServiceUsage
    extend ActiveSupport::Concern

    def bill_bw_by_lb?
      !has_iptable_rules?
    end

    # Currently only used for display purposes.
    def bandwidth_this_period
      expire_by_env = Rails.env.production? ? 1.hour : 2.minutes
      Rails.cache.fetch("service_bandwidth_#{id}", expires_in: expire_by_env) do
        bw_usage = BillingUsage.where("products.resource_kind = 'bandwidth' AND subscription_products.subscription_id IN(?) AND period_end >= ?", subscriptions.map(&:id), TimeHelpers.first_day_of_month).joins(:subscription_product, :product).sum(:qty_total)
        bw_usage
      end
    end

    # Determine bandwidth usage during a given period
    #
    # period = { start: '', end: '' }
    def billing_current_bandwidth
      service_usage = 0.0
      ingress_rules.each do |ingress|
        service_usage += ingress.metric_bytes_out
      end
      service_usage.zero? ? service_usage : (service_usage / Numeric::GIGABYTE).round(8)
    rescue => e
      ExceptionAlertService.new(e, 'e8956ca1ad04c052').perform
      0.0
    end

    def current_storage
      volumes.sum(:usage)
    end

    def run_rate(reset_cache = false)
      cache_key = "s_run_rate_#{id}"
      Rails.cache.fetch(cache_key, force: reset_cache, expires_in: 2.hours) do
        subscriptions.all_active.inject(0) { |sum,item| sum += item.run_rate }
      end
    end

    def auto_scale_quote
      return nil if subscriptions.empty?
      mem_packages = BillingPackage.find_by_plan(user.billing_plan, {memory: memory + 1, cpu: cpu})
      cpu_packages = BillingPackage.find_by_plan(user.billing_plan, {memory: memory, cpu: cpu + 0.1})

      return nil if mem_packages.empty? && cpu_packages.empty?

      current_price = subscriptions.first.package_subscription.current_price&.price
      return nil if current_price.nil?
      base_rate = 0.0
      unless mem_packages.empty?
        product = mem_packages.first&.product
        if product
          p = product.price_lookup user, region
          p = p.price if p
          base_rate = p if p && p > base_rate
        end
      end

      unless cpu_packages.empty?
        product = cpu_packages.first&.product
        if product
          p = product.price_lookup user, region
          p = p.price if p
          base_rate = p if p && p > base_rate
        end
      end

      if can_scale?
        base_rate = base_rate * containers.count
        scale_price = current_price * 2  # simulate adding 1 additional container
        base_rate = base_rate > scale_price ? base_rate : scale_price
      end
      base_rate
    rescue => e
      ExceptionAlertService.new(e, '208a3ca3358b7c3b').perform
      nil
    end

  end
end
