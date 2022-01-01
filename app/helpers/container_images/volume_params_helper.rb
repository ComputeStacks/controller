module ContainerImages::VolumeParamsHelper

  def new_container_image_volume_path(image)
    return nil if image.nil?
    "#{container_image_path(image)}/volume_params/new"
  end

  def edit_container_image_volume_path(volume)
    return "/container_images" if volume.nil?
    "#{container_image_volume_path(volume)}/edit"
  end

  def container_image_volume_path(volume)
    return "/container_images" if volume.nil?
    "#{container_image_path(volume.container_image)}/volume_params/#{volume.id}"
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

end