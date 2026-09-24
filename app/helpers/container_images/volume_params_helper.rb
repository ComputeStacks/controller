module ContainerImages::VolumeParamsHelper
  # @param [ContainerImage] image
  def container_image_volumes_path(image)
    return container_images_path if image.nil?
    "#{container_image_path(image)}/volume_params"
  end

  # @param [ContainerImage] image
  def new_container_image_volume_path(image)
    return container_images_path if image.nil?
    "#{container_image_volumes_path(image)}/new"
  end

  # @param [ContainerImage::VolumeParam] volume
  def edit_container_image_volume_path(volume)
    return container_images_path if volume.nil?
    "#{container_image_volume_path(volume)}/edit"
  end

  # @param [ContainerImage::VolumeParam] volume
  def container_image_volume_path(volume)
    return container_images_path if volume.nil?
    "#{container_image_volumes_path(volume.container_image)}/#{volume.id}"
  end

  ##
  # Retroactively create this template volume on every already-deployed service of the
  # image. Built on `container_image_volume_path`, which resolves through the request-aware
  # `container_image_path`, so this lands on the admin or the non-admin controller depending
  # on where the user actually is.
  #
  # @param [ContainerImage::VolumeParam] volume
  def cascade_container_image_volume_path(volume)
    return container_images_path if volume.nil?
    "#{container_image_volume_path(volume)}/cascade"
  end

  def borg_strategies
    [
      {
        id: "mysql", label: "MySQL"
      },
      {
        id: "postgres", label: "Postgresql"
      },
      {
        id: "file", label: "Files"
      },
      {
        id: "custom", label: "Custom"
      }
    ]
  end

  def image_mountable_volumes(volume)
    mountable = []
    volume.container_image.dependencies.each do |i|
      i.volumes.each do |ii|
        mountable << {id: ii.id, csrn: ii.csrn, label: ii.label}
      end
    end
    mountable
  end

  def order_volume_mountable(volume_param_csrn)
    Csrn.locate volume_param_csrn
    # TODO: Include template csrns and project volumes
    #       csrn:caas:template:vol:webroot:9
    #       csrn:caas:project:vol:webroot:9
    Volume.all.map { |i| [i.csrn, i.csrn] }
    {"Order Volumes" => [], "Project Volumes" => []}
  end
end
