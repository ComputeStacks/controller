module Admin::ProductsHelper

  def admin_package_path(package)
    "/admin/products/#{package.product.id}/billing_packages/#{package.id}"
  end

end