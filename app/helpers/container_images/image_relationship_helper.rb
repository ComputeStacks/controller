module ContainerImages
  module ImageRelationshipHelper

    # @param [ContainerImage] image
    def container_image_relationships_path(image)
      return container_images_path if image.nil?
      "#{container_image_path(image)}/image_relationships"
    end

    # @param [ContainerImage::ImageRel] rel
    def container_image_relationship_path(rel)
      return container_images_path if rel.nil?
      "#{container_image_relationships_path(rel.container_image)}/#{rel.id}"
    end

    # @param [ContainerImage] image
    def new_container_image_relationship_path(image)
      return nil if image.nil?
      "#{container_image_relationships_path(image)}/new"
    end

    # @param [ContainerImage::ImageRel] rel
    def edit_container_image_relationship_path(rel)
      return container_images_path if rel.nil?
      "#{container_image_relationship_path(rel)}/edit"
    end

    # @param [ContainerImage::ImageRel] dependency
    def image_relationship_label(dependency)
      if dependency.default_variant.nil?
        "#{dependency.dependency.label} (#{dependency.dependency.default_variant.label})"
      else
        "#{dependency.dependency.label} (#{dependency.default_variant.label})"
      end
    end

    def image_relationship_parent_list(image)
      links = []
      image.parent_containers.order(:name).each do |i|
        links << link_to(i.label, container_image_path(i))
      end
      links.join(" | ").html_safe
    end

  end
end
