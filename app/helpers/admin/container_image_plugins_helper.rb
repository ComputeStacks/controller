module Admin::ContainerImagePluginsHelper

  def image_plugin_product_link(plugin)
    return "..." if plugin.product.nil?
    link_to plugin.product.label, admin_product_path(plugin.product)
  end

end
