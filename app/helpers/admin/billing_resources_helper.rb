module Admin::BillingResourcesHelper

  def available_products(billing_plan, current_product = nil)
    products = []
    products_in_use = billing_plan.products.pluck(:id)
    Product.order(:name).each do |i|
      products << i if current_product == i
      products << i unless products_in_use.include?(i.id)
    end
    products
  end

  def link_to_package(package)
    link_to package.product.name, admin_package_path(package)
  end

  def resource_price_form_helper(price)
    if price.billing_resource.product.is_aggregated
      "Price is per-unit, as it's consumed. It will be aggregated and billed monthly."
    else
      case price.term
      when 'hour'
        "Price is per-hour"
      when 'month'
        "Price is per-month"
      end
    end
  end

end
