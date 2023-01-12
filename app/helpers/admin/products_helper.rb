module Admin::ProductsHelper

  def edit_admin_product_path(product)
    admin_product_path(product) + "/edit"
  end

  def admin_products_path
    "/admin/products"
  end

  def admin_product_path(product)
    admin_products_path + "/#{product.id}-#{product.label.parameterize}"
  end

  def admin_package_path(package)
    admin_products_path + "/#{package.product.id}/billing_packages/#{package.id}"
  end

  def admin_product_image_link_list(product)
    return "..." if product.nil? || !product.is_image?
    return "..." if product.container_images.empty?
    ar = []
    product.container_images.each do |image|
      ar << link_to(image.label, admin_container_image_path(image))
    end
    ar.join(", ").html_safe
  end

  def product_options_for_select
    [
      %w(Image image),
      ["Metered Resource", "resource"],
      %w(Package package),
      %w(Addon addon)
    ].sort
  end

  def product_addon_plugin_links(product)
    return "" unless product.is_addon?
    return "" if product.image_plugins.empty?
    link_array = product.image_plugins.map do |i|
      link_to i.name.titleize, "/admin/container_image_plugins/#{i.id}"
    end
    link_array.join(", ").html_safe
  end

end
