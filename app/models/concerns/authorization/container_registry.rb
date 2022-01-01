module Authorization
  module ContainerRegistry
    extend ActiveSupport::Concern
    include Authorization::Generic

    class_methods do

      # @param [User] current_user
      # @return [Array<ContainerRegistry>]
      def find_all_for(current_user)
        where("container_registries.user_id = ? OR (container_registry_collaborators.active = true AND container_registry_collaborators.user_id = ?)", current_user.id, current_user.id).joins("LEFT JOIN container_registry_collaborators ON container_registries.id = container_registry_collaborators.container_registry_id").distinct
      end
    end

    # @param [User] current_user
    # @return [Boolean]
    def can_view?(current_user)
      return false if current_user.nil?
      return true if current_user == user || current_user.is_admin
      container_registry_collaborators.where(user_id: current_user.id, active: true).exists?
    end

  end
end
