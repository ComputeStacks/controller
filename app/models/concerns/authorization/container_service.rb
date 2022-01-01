module Authorization
  module ContainerService
    extend ActiveSupport::Concern
    include Authorization::Generic

    class_methods do

      # @param [User] current_user
      # @return [Array<Deployment::ContainerService>]
      def find_all_for(current_user)

        where("deployments.status != 'deleting' AND (deployments.user_id = ? OR (deployment_collaborators.active = true AND deployment_collaborators.user_id = ?))", current_user.id, current_user.id).joins(:deployment, "LEFT JOIN deployment_collaborators ON deployments.id = deployment_collaborators.deployment_id").distinct

      end

    end

    # @param [User] current_user
    # @return [Boolean]
    def can_view?(current_user)
      return false if current_user.nil?
      return true if current_user == deployment.user || current_user.is_admin
      return false if deployment.nil? || deployment.status == 'deleting' || deployment.deleting?
      deployment.can_view? current_user
    end

  end
end
