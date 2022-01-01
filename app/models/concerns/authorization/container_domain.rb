module Authorization
  module ContainerDomain
    extend ActiveSupport::Concern
    include Authorization::Generic

    class_methods do

      # @return [Array<ContainerDomain>]
      def find_all_for(current_user)
        where("deployment_container_domains.user_id = ? OR deployments.user_id = ? OR (deployment_collaborators.active = true AND deployment_collaborators.user_id = ?)", current_user.id, current_user.id, current_user.id).joins(:container_service, "LEFT JOIN deployments ON deployments.id = deployment_container_services.deployment_id", "LEFT JOIN deployment_collaborators ON deployments.id = deployment_collaborators.deployment_id").distinct
      end

    end

    # @param [User] current_user
    # @return [Boolean]
    def can_view?(current_user)
      return false if current_user.nil?
      return true if current_user == user || current_user.is_admin
      return false if container_service.nil?
      container_service.can_view? current_user
    end

  end
end
