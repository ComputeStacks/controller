module Authorization
  module Alert
    extend ActiveSupport::Concern
    include Authorization::Generic

    # @param [User] current_user
    # @return [Boolean]
    def can_view?(current_user)
      return false if current_user.nil?
      return true if current_user.is_admin
      if container
        return true if container.user == current_user
      end
      if sftp_container
        return true if sftp_container.user == current_user
      end
      false
    end

  end
end
