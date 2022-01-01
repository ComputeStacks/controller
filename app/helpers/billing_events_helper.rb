module BillingEventsHelper

  def billing_event_title(billing_event, perspective = 'subscription')

    from_status = billing_event.from_status
    to_status = billing_event.to_status
    source_product = billing_event.source_product
    destination_product = billing_event.destination_product
    from_phase = billing_event.from_phase
    to_phase = billing_event.to_phase
    from_resource_qty = billing_event.from_resource_qty
    to_resource_qty = billing_event.to_resource_qty
    resource_type = billing_event.resource_type

    if perspective == 'subscription' || billing_event.subscription_product.nil?
      msg = billing_event.url.nil? ? billing_event.subscription.label : "<a href='#{billing_event.url}'>#{billing_event.subscription.label}</a>"
    else
      msg = billing_event.subscription_product.product.label
    end

    # Track Status
    if from_status || to_status
      s1 = if from_status.nil?
             'none'
           else
             from_status ? 'active' : 'inactive'
           end
      s2 = if to_status.nil?
             'none'
           else
             to_status ? 'active' : 'inactive'
           end
      msg = "#{msg} status moved from #{s1} to #{s2}."
    end

    # Track Product
    if source_product || destination_product
      if perspective == 'subscription' || billing_event.subscription_product.nil?
        msg = "#{msg} product moved from #{source_product.nil? ? 'None' : source_product.label} to #{destination_product.nil? ? 'None' : destination_product.label}."
      else
        msg = "#{msg} was migrated to #{destination_product.nil? ? 'None' : destination_product.label}."
      end
    end

    # Track Phase
    if from_phase || to_phase
      msg = "#{msg} moved from #{from_phase} to #{to_phase}."
    end

    # Resource Qty
    if from_resource_qty || to_resource_qty
      msg = "#{msg} quantity changed from #{from_resource_qty} to #{to_resource_qty} #{resource_type}."
    end
    msg
  end

end
