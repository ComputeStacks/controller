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

  def image_mountable_volumes(volume)
    mountable = []
    volume.container_image.dependencies.each do |i|
      i.volumes.each do |ii|
        mountable << { id: ii.id, csrn: ii.csrn, label: ii.label }
      end
    end
    mountable
  end

  def order_volume_mountable(volume_param_csrn)
    volparam = Csrn.locate volume_param_csrn
    # TODO: Include template csrns and project volumes
    #       csrn:caas:template:vol:webroot:9
    #       csrn:caas:project:vol:webroot:9
    Volume.all.map { |i| [i.csrn, i.csrn] }
    ar = { 'Order Volumes' => [], 'Project Volumes' => [] }
  end




end
