module BillingUsageServices

  ##
  # Collect usage metric data
  class CollectUsageService

    attr_accessor :perform_for #generic attribute to store obj we're processing

    def initialize(perform_for = nil)
      self.perform_for = perform_for
    end

    def perform
      subscription_ids = [] # Track which subscription we collect usage from
      if perform_for.is_a?(User) # Allow processing usage for a single user
        perform_for.deployments.each do |i|
          i.deployed_containers.each do |c|
            next if subscription_ids.include?(c.id)
            subscription_ids << c.id
            gen_usage!(c)
          end
        end
        offline_storage(perform_for)
      elsif !perform_for.nil? # Allow processing usage for a single object
        gen_usage!(perform_for)
      else # Otherwise, process usage for ALL services.
        Deployment::Container.where('subscription_id is not null and deployments.user_id is not null').joins(:deployment).each do |c|
          next if subscription_ids.include?(c.id)
          subscription_ids << c.id
          gen_usage!(c)
        end
        User.all.each do |user|
          offline_storage(user)
        end
        true
      end
    end

    private

    ##
    # Generate usage for a given object
    #
    def gen_usage!(obj)
      end_time = Time.now.utc
      user = obj.user
      return false if user.nil?
      billing_plan = user.billing_plan
      return true if billing_plan.nil? # Skip if the user has no billing plan
      subscription = obj.subscription
      return true if subscription.nil? # Skip for no subscription
      return true unless subscription.active # Skip if it's inactive

      # Ensure container subscriptions has storage & backup products.
      if obj.is_a?(Deployment::Container)
        storage_product = Product.lookup(user.billing_plan, 'storage')
        local_disk_product = Product.lookup user.billing_plan, 'local_disk'
        backup_product = Product.lookup(user.billing_plan, 'backup')
        if storage_product && !subscription.subscription_products.where(product_id: storage_product.id).exists?
          subscription.subscription_products.create!(product: storage_product, allow_nil_phase: true)
        end
        if local_disk_product && !subscription.subscription_products.where(product_id: local_disk_product.id).exists?
          subscription.subscription_products.create!(product: local_disk_product, allow_nil_phase: true)
        end
        if backup_product && !subscription.subscription_products.where(product_id: backup_product.id).exists?
          subscription.subscription_products.create!(product: backup_product, allow_nil_phase: true)
        end
      end

      subscription.subscription_products.where(active: true).each do |sb|
        sb.generate_usage! end_time
      end
      true
    end

    ##
    # Track detached volumes & backups.
    #
    # Notes:
    #   - If Backup product does not exist, it will fall back to storage product.
    #   - Detached local volumes will use the Storage price.
    #
    def offline_storage(user)
      volumes = user.volumes.where("detached_at is not null")
      # Determine if this user requires this step.
      return false if volumes.empty?

      storage_product = Product.lookup(user.billing_plan, 'storage')
      backup_product = Product.lookup(user.billing_plan, 'backup')

      # allow to proceed if 1 of the 2 exists (at least get _some_ billing data).
      return false if storage_product.nil? && backup_product.nil?

      volumes.each do |vol|

        end_time = Time.now.utc # Sync all services to a single end date.

        subscription = vol.subscription
        if subscription.nil?
          subscription = vol.create_subscription!(user: vol.user, label: 'Detached Volume', service_key: 'offline_volume', active: false)
          vol.update subscription: subscription
        end

        if storage_product
          storage_sb = subscription.subscription_products.find_by(product: storage_product)
          storage_sb = subscription.subscription_products.create!(product: storage_product, allow_nil_phase: true) if storage_sb.nil?
          storage_prev_record = storage_sb.billing_usages.order(created_at: :desc).first
        else
          storage_sb = nil
          storage_prev_record = nil
        end

        if backup_product
          backup_sb = subscription.subscription_products.find_by(product: backup_product)
          backup_sb = subscription.subscription_products.create!(product: backup_product, allow_nil_phase: true) if backup_sb.nil?
          backup_prev_record = backup_sb.billing_usages.order(created_at: :desc).first
        else
          backup_sb = nil
          backup_prev_record = nil
        end

        start_time = vol.detached_at
        next if start_time.nil? # should _never_ happen.
        qty = 0.0
        #product_rate = sb.current_price(raw_units)
        product_rate = nil
        sb = nil
        next if storage_product.nil? || storage_sb.nil?
        start_time = storage_prev_record.period_end + 1.second if storage_prev_record && (storage_prev_record.period_end > vol.detached_at)
        qty = vol.usage
        sb = storage_sb

        next if sb.billing_resource.nil? # Means this is not setup in the billing plan.

        unless sb.billing_usages.where('period_start > ? and period_end <= ?', start_time, end_time).exists?
          product_rate = sb.current_price(qty)

          # Convert time difference into fractional hour.
          period_length = ((end_time - start_time).to_f / 1.hour).round(4)

          # Multiple price by fractional hour to get adjusted price, then multiple by quantity.
          usage_total = ((product_rate.price * period_length) * qty).round(8)

          new_usage = sb.billing_usages.new(
              user: user,
              period_start: start_time,
              period_end: end_time,
              external_id: subscription.external_id,
              qty: qty,
              qty_total: qty,
              rate: product_rate.price,
              total: usage_total
          )
          # For zero usage, mark as processed.
          if usage_total.zero?
            new_usage.processed = true
            new_usage.processed_on = Time.now
          end
          new_usage.save
        end # END check for existing usage in this period.

        subscription.update(active: true) unless subscription.active

        # Ensure we have a backup subscription to update.
        next if backup_product.nil?
        next if !defined?(backup_sb) || backup_sb.nil?

      end # END volumes.each
    end

  end
end
