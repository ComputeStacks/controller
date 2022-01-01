module Authorization
  module DnsZone
    extend ActiveSupport::Concern
    include Authorization::Generic

    class_methods do

      # @param [User] current_user
      # @return [Array<Dns::Zone>]
      def find_all_for(current_user)
        where("dns_zones.user_id = ? OR (dns_zone_collaborators.active = true AND dns_zone_collaborators.user_id = ?)", current_user.id, current_user.id).joins("LEFT JOIN dns_zone_collaborators ON dns_zones.id = dns_zone_collaborators.dns_zone_id").distinct
      end

    end

    # @param [User] current_user
    # @return [Boolean]
    def can_view?(current_user)
      return false if provision_driver.nil?
      return false if current_user.nil?

      if name == "computestacks.cloud" || name == "usr.cloud"
        return false unless current_user.is_support_admin?
      end

      return true if current_user == user || current_user.is_admin
      dns_zone_collaborators.where(user_id: current_user.id, active: true).exists?
    end

    # Can the system perform automated updates on this zone?
    # If the saved state is not blank, then the user has made changes without commiting them.
    # We do not want to save that for them, so we can't modify if they have no commited their changes.
    def system_can_update?
      saved_state.blank?
    end

  end
end
