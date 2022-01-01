module Admin::ContainerImagesHelper

  def admin_container_image_path(i)
    "/admin/container_images/#{i.id}-#{i.name.parameterize}"
  end

end