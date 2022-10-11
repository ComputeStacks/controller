module ContainerImages
  module ImageRelationshipHelper

    # @param [ContainerImage::ImageRel] dependency
    def image_relationship_label(dependency)
      if dependency.default_variant.nil?
        "#{dependency.dependency.label} (#{dependency.dependency.default_variant.label})"
      else
        "#{dependency.dependency.label} (#{dependency.default_variant.label})"
      end
    end

  end
end
