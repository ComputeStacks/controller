module BillingUsageServices
  ##
  # Aggregate Billing Usage Data
  class AggregateUsageService

    attr_accessor :audit,
                  :clean_bypassed_users, # if true, will set users with `bypass_billing` to `processed`.
                  :event,
                  :restrict_to_month, # If true, will restrict this to the last day of the month
                  :result

    def initialize(enforce_day = true)
      self.audit = nil
      self.clean_bypassed_users = true
      self.event = nil
      self.restrict_to_month = enforce_day
      self.result = []
    end

    def perform
      return false unless can_perform?

      build_event!
      aggregate!

      unless Setting.webhook_billing_usage.value.blank?
        WebHookJob.perform_later(Setting.webhook_billing_usage, event.id)
      end

      if Setting.billing_hooks.include?(:process_usage)
        Setting.call_billing_hook :process_usage, result
      end
      true
    end

    private

    def aggregate!
      processed_records = []
      aggregated = []
      billing_users = []
      if clean_bypassed_users
        # Mark users with bypassed billing as having processed data.
        BillingUsage.where(users: { bypass_billing: true }, processed: false).joins(:user).update_all processed: true, processed_on: Time.now
      end
      # Aggregate usage by (subscription, product)
      BillingUsage.unscoped.select("distinct on (subscription_product_id) id, subscription_product_id, processed").where(processed: false).each do |i|
        aggreg_total = BillingUsage.unscoped.select("SUM(total) as bill_total, SUM(qty) as bill_qty").find_by(subscription_product_id: i.subscription_product_id, processed: false)
        next if aggreg_total.nil? || aggreg_total.bill_total < 0.01 # 1 Cent is the smallest unit we will process.

        pstart = nil
        pend = nil
        ext_id = nil
        items = []
        BillingUsage.where(users: { bypass_billing: false }, subscription_product_id: i.subscription_product_id, processed: false).joins(:user).each do |usage|
          billing_users << usage.user if usage.user && !billing_users.include?(usage.user)
          pstart = usage.period_start if pstart.nil? || usage.period_start < pstart
          pend = usage.period_end if pend.nil? || usage.period_end > pend
          next if pstart.nil? || pend.nil?

          ext_id = usage.external_id if ext_id.nil? && !usage.external_id.nil?
          processed_records << usage
          items << {
              id: usage.id,
              rate: usage.rate.to_f,
              rate_period: usage.rate_period.to_i,
              qty: usage.qty.to_f,
              total: usage.total.to_f,
              period_start: usage.period_start.utc,
              period_end: usage.period_end.utc
          }
        end
        sub_product = i.subscription_product
        next if sub_product.nil?

        sub = sub_product.subscription
        next if sub.nil?

        product = sub_product.product
        next if product.nil?
        next if sub_product.billing_resource.nil? || sub_product.user.nil?

        aggregated << {
            subscription_id: sub.id,
            subscription_product_id: i.subscription_product_id,
            product: { id: product.id, name: product.name, external_id: product.external_id },
            billing_resource: {
                id: sub_product.billing_resource.id,
                external_id: sub_product.billing_resource.external_id,
                billing_plan_id: sub_product.billing_resource.billing_plan_id
            },
            container_service_id: sub.linked_obj.is_a?(Deployment::Container) ? sub.linked_obj.service&.id : nil,
            container_id: sub.linked_obj.is_a?(Deployment::Container) ? sub.linked_obj.id : nil,
            user: {
              id: sub_product.user.id,
              external_id: sub_product.user.external_id,
              email: sub_product.user.email,
              labels: sub_product.user.labels
            },
            external_id: ext_id,
            total: aggreg_total.bill_total.to_f,
            qty: aggreg_total.bill_qty.to_f,
            period_start: pstart.utc,
            period_end: pend.utc,
            usage_items: items
        }
      end
      if event
        event.event_details.create!(data: aggregated.to_json, event_code: 'af5dbfa43bebd5f5')
        event.done!
      end
      self.result = aggregated.map(&:with_indifferent_access)
      # Even if it does not succeed, you still need to mark them as processed because the `process_usage!()` function does not
      # check if data already exists before processing it; you can't run it more than once.
      billing_users.each do |u|
        BillingUsage.where(user: u, processed: false).update_all processed: true, processed_on: Time.now
      end
    end

    def build_event!
      self.audit = Audit.create!(event: 'created') if audit.nil?
      self.event = EventLog.create!(
        audit: audit,
        locale: 'system.process_uage',
        status: 'pending', # Webhook job will update this
        event_code: 'af5dbfa43bebd5f5'
      )
    end

    def can_perform?
      !restrict_to_month || (restrict_to_month && (Date.today == Date.today.end_of_month))
    end

  end

end
