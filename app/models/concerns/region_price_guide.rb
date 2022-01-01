module RegionPriceGuide
  extend ActiveSupport::Concern

  def user_pricing(user)
    data = { 'containers' => { 'packages' => [], 'resources' => {} }, 'virtual_machines' => { 'packages' => [], 'resources' => {} } }

    packages = BillingPackage.find_by_plan(user.billing_plan)
    packages.each do |i|
      pp = i.product.price_lookup(user, self)
      p = {
          'id' => i.product_id,
          'name' => i.product.label,
          'price' => pp.nil? ? BigDecimal('0.0') : pp.price,
          'term' => (pp.nil? || i.product&.resource_kind == 'bandwidth') ? '' : pp.term
      }
      item = i.attributes
      item.delete('id')
      item.delete('product_id')
      item.delete('created_at')
      item.delete('updated_at')
      p.merge!(item)
      data['containers']['packages'] << p
    end

    %w(cpu memory storage backup bandwidth).each do |i|
      resource = Product.lookup(user.billing_plan, i)
      if resource
        pp = resource.price_lookup(user, self)
        data['containers']['resources'][i] = pp.nil? ? BigDecimal('0.0') : pp.price
      end
    end
    data
  end

end
