module BillingHelper

  # Stylize the display of the current price.
  #
  # @param [Region] region
  # @param [Product] product
  # @type [User] current_user
  def display_current_price(region, product, user = current_user)
    return I18n.t('common.free') if product.nil?
    current_price = product.price_lookup(user, region)
    final_price = product.price_phases(user, region)[:final].first
    return formatted_product_price(region, product) if current_price == final_price
    "<strike>#{formatted_final_price(region, product)}</strike><br />#{formatted_product_price(region, product)}".html_safe
  end

  # Shows the CURRENT price.
  # @param [Region] region
  # @param [Product] product
  def formatted_product_price(region, product)
    formatted_product_price_resource product.price_lookup(current_user, region)
  end

  def formatted_product_price_resource(price_resource)
    return I18n.t('common.free') if price_resource.nil? || price_resource.price.zero?
    unit = price_resource.product.is_aggregated ? price_resource.product.unit_type : I18n.t("billing.#{price_resource.term}")
    format_currency(price_resource.price, price_resource.price_precision) + " /" + unit
  end

  def price_resource_time_limit(price_resource)
    if price_resource.nil? || price_resource.billing_phase.time_unit.nil?
      %q(<span style="font-size:20px;line-height:10px;" title="No time limit.">-</span>).html_safe
    else
      billable_phase_price_quote price_resource.billing_phase
    end
  end

  # Shows the FINAL price.
  #
  # @param [Region] region
  # @param [Product] product
  # @type [User] current_user
  def formatted_final_price(region, product, user = current_user)
    price_resource = product.price_phases(user, region)[:final].first
    format_currency(price_resource.price, price_resource.price_precision) + " /" + I18n.t("billing.#{price_resource.term}")
  rescue
    I18n.t('common.free')
  end

  # TODO: Bring this into the above method.
  #
  # This is currently expected to return a BigDecimal or Float.
  def formatted_hourly_price(product, region, user = current_user)
    price_resource = product.price_lookup(user, region)
    if price_resource.nil?
      0.0
    else
      price_resource.price / product.unit
    end
  end

  def billable_phase_price_quote(phase, user = current_user)
    the_time = current_user.phase_started.nil? ? phase.time_unit.from_now : (user.phase_started + phase.time_unit)
    "<span>For #{distance_of_time_in_words(Time.now, the_time).gsub(' ago', '')}</span>".html_safe
  end

  def selectable_currency_list
    bp = current_user.nil? ? BillingPlan.default : current_user.billing_plan
    currencies = bp.nil? ? [ ENV['CURRENCY'] ] : bp.available_currencies
    available_currencies(currencies)
  end

end
