module Admin::BillingPlansHelper

  def available_currencies(filter = [])
    table = Money::Currency.table
    table = table.select { |_, k| filter.include?(k[:iso_code]) } unless filter.empty?
    table.map { |_, k| [k[:name], k[:iso_code]] }
  end

  # @param [BillingPhase] phase
  def phase_default_price(phase)
    price = phase.prices.where(currency: ENV['CURRENCY']).order(Arel.sql("max_qty asc nulls last")).first
    price = phase.prices.order(Arel.sql("max_qty asc nulls last")).first if price.nil? && phase.prices.exists? # Fallback to not including default currency.
    return 0.0 if price.nil?
    return 0.0 if price.price.zero?
    p = '%.5f' % price.price
    phase.product&.resource_kind == 'bandwidth' ? p : "#{p} /#{I18n.t("billing.#{price.term}")}"
  rescue => e
    ExceptionAlertService.new(e, '2502c997f429c904').perform
    0.0
  end

  # @param [BillingPhase] phase
  def currency_price_table(phase, currency)
    result = {
      'header' => phase.prices.where(currency: currency).select(:max_qty).order(Arel.sql("max_qty ASC NULLS LAST")).map { |i| i.max_qty },
      'regions' => []
    }
    phase.regions.each do |region|
      val = [region.name]
      result['header'].each do |h|
        val << '-'
      end
      region.billing_resource_prices.where(billing_phase: @phase, currency: currency).order(Arel.sql("max_qty ASC NULLS LAST")).each_with_index do |price, i|
        header_index = 0
        result['header'].each_with_index do |i,k|
          if price.max_qty.nil? && i.nil?
            header_index = k
          elsif price.max_qty == i
            header_index = k
          end
        end
        p_formatted = Monetize.parse("#{currency} #{price.price}").format
        if price.pre_paid?
          p_formatted = "#{p_formatted} /#{I18n.t("billing.#{price.term}")}"
        else
          p_formatted = price.product.is_aggregated ? "#{p_formatted[0]}#{price.price}" : "#{p_formatted[0]}#{'%.6f' % price.price} /#{I18n.t("billing.#{price.term}")}"
        end
        val[header_index + 1] = {
          'title' => p_formatted,
          'href' => "#{@base_url}/billing_phases/#{@phase.id}/billing_resource_prices/#{price.id}/edit"
        }
      end
      result['regions'] << val
    end
    empty_regions = []
    phase.prices.order(Arel.sql("max_qty ASC NULLS LAST")).each do |i|
      empty_regions << i if i.regions.empty?
    end
    unless empty_regions.empty?
      val = ['Unassigned']
      result['header'].each do |h|
        val << '-'
      end
      empty_regions.each do |price|
        # Find index
        header_index = 0
        result['header'].each_with_index do |i, k|
          if price.max_qty.nil? && i.nil?
            header_index = k
          elsif price.max_qty == i
            header_index = k
          end
        end
        val[header_index + 1] = {
          'title' => Monetize.parse("#{currency} #{price.price}").format,
          'href' => "#{@base_url}/billing_phases/#{@phase.id}/billing_resource_prices/#{price.id}/edit"
        }
      end
      result['regions'] << val
    end
    result
  end

  def billing_plan_groups(plan)
    return 'unassigned' if plan.user_groups.empty?
    g = plan.user_groups.map do |i|
      i.name
    end
    g.join(', ')
  end

  def currency_table_qty(qty)
    return "&infin;".html_safe if qty.nil? || qty < 0
    return qty.to_i if qty % 2 == 0
    qty
  end

end
