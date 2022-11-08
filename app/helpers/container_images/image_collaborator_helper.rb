module ContainerImages
  module ImageCollaboratorHelper

    # @param [ContainerImageCollaborator] entry
    def container_image_collaborators_path(image)
      return container_images_path if image.nil?
      "#{container_image_path(image)}/collaborators"
    end

    # @param [ContainerImage] image
    def new_container_image_collaborator_path(image)
      return container_images_path if image.nil?
      "#{container_image_collaborators_path(image)}/new"
    end

    # @param [ContainerImageCollaborator] entry
    def container_image_collaborator_path(collab)
      return container_images_path if collab.nil?
      "#{container_image_path(entry.container_image)}/collaborators/#{collab.id}"
    end

    # @param [ContainerImageCollaborator] entry
    def edit_container_image_collaborator_path(collab)
      return container_images_path if collab.nil?
      "#{container_image_collaborator_path(collab)}/edit"
    end

  end
end
