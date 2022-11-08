module Admin::ProductsHelper

  def admin_package_path(package)
    "/admin/products/#{package.product.id}/billing_packages/#{package.id}"
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

end
