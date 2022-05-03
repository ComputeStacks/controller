module Authorization
  module Deployment
    extend ActiveSupport::Concern
    include Authorization::Generic

    class_methods do

      # @param [User] current_user
      # @return [Array<Deployment>]
      def find_all_for(current_user)
        where("status != 'deleting' AND (deployments.user_id = ? OR (deployment_collaborators.active = true AND deployment_collaborators.user_id = ?))", current_user.id, current_user.id).joins("LEFT JOIN deployment_collaborators ON deployments.id = deployment_collaborators.deployment_id").distinct
      end
    end

    # @param [User] current_user
    # @return [Boolean]
    def can_view?(current_user)
      return false if current_user.nil?
      return true if current_user.is_admin
      return false if status == 'deleting' || deleting?
      return true if current_user == user
      deployment_collaborators.where(active: true, user_id: current_user.id).exists?
    end

    # @param [User] current_user
    # @return [Boolean]
    def can_delete?(current_user)
      return false if current_user.nil?
      return true if current_user.is_admin
      return true if current_user == user
      deployment_collaborators.where(active: true, user_id: current_user.id).exists?
    end

  end
end
