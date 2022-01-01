object false

node :products do
  @products.map do |i|
    partial 'api/admin/products/product', object: i
  end
end
