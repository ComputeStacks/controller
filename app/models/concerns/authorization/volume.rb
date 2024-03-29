module Authorization
  module Volume
    extend ActiveSupport::Concern
    include Authorization::Generic

    class_methods do

      # @return [Array<Volume>]
      def find_all_for(current_user)
        where("volumes.user_id = ? OR deployments.user_id = ? OR (deployment_collaborators.active = true AND deployment_collaborators.user_id = ?)", current_user.id, current_user.id, current_user.id).joins(:container_services, "LEFT JOIN deployments ON deployments.id = deployment_container_services.deployment_id", "LEFT JOIN deployment_collaborators ON deployments.id = deployment_collaborators.deployment_id").distinct
      end

    end

    # @return [Boolean]
    def can_view?(current_user)
      return false if current_user.nil?
      return true if current_user == user || current_user.is_admin
      return false if container_services.empty?
      cv = false
      container_services.each do |i|
        if i.can_view?(current_user)
          cv = true
          break
        end
      end
      cv
    end

  end
end
