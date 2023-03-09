module Authorization
  module ContainerImage
    extend ActiveSupport::Concern
    include Authorization::Generic

    class_methods do

      # @param [User] current_user
      # @return [Array<ContainerImage>]
      def find_all_for(current_user, include_public = false)
        if include_public
          where("(container_images.user_id is null and container_images.active = true) OR (container_images.user_id = ? OR (container_image_collaborators.active = true AND container_image_collaborators.user_id = ?))", current_user.id, current_user.id).joins("LEFT JOIN container_image_collaborators ON container_images.id = container_image_collaborators.container_image_id").distinct
        else
          where("container_images.user_id = ? OR (container_image_collaborators.active = true AND container_image_collaborators.user_id = ?)", current_user.id, current_user.id).joins("LEFT JOIN container_image_collaborators ON container_images.id = container_image_collaborators.container_image_id").distinct
        end
      end

    end

    ##
    # Who can view this image?
    #
    # Admins
    # Owners
    # Public + active
    # Inactive + in-use
    #
    # @param [User] current_user
    # @return [Boolean]
    def can_view?(current_user)
      return true if active && user.nil?
      return false if current_user.nil?
      return true unless container_image_collections.available.empty?
      return true if current_user.is_admin || user == current_user
      return true if container_image_collaborators.where(user_id: current_user.id, active: true).exists?

      # Looks at user-owned projects
      return true if current_user.deployed_images.select(:id).pluck(:id).include?(id)

      # not directly added as a collaborator, but images used in a project they collaborate on
      current_user.project_image_collaborations.select(:id).pluck(:id).include? id
    end

    # @param [User] current_user
    # @return [Boolean]
    def can_edit?(current_user)
      return false if current_user.nil?
      return true if current_user == user || current_user.is_admin
      container_image_collaborators.where(user_id: current_user.id, active: true).exists?
    end

  end
end
