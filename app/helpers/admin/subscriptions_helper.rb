module Admin::SubscriptionsHelper

  def subscription_obj_link(subscription)
    ref_obj = subscription.linked_obj
    return '...' if ref_obj.nil?
    case ref_obj.class.to_s
    when 'Deployment::Container'
      link_to ref_obj.name, "/admin/containers/#{ref_obj.id}"
    else
      '...'
    end
  end

  def admin_subscriptions_path(subscription)
    subscription.label.blank? ? "/admin/subscriptions/#{subscription.id}" : "/admin/subscriptions/#{subscription.id}-#{subscription.label.parameterize}"
  end

  def subscription_cost_period(subscription)
    date = Date.new(Date.today.year, Date.today.month, 1)
    total = subscription.billing_usages.where('period_start > ?', date).sum(:total)
    format_currency(total, 4)
  end

  def subscription_unprocessed_cost(subscription)
    date = Date.new(Date.today.year, Date.today.month, 1)
    total = subscription.billing_usages.where('processed = false and period_start > ?', date).sum(:total)
    format_currency(total, 4)
  end

  def subscription_events_period(subscription)
    date = Date.new(Date.today.year, Date.today.month, 1)
    subscription.billing_events.where('created_at > ?', date).count
  end

end
