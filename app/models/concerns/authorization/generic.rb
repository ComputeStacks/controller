module Authorization
  ##
  # Generic Resource Authorization
  #
  module Generic
    extend ActiveSupport::Concern

    class_methods do

      # @return [Array]
      def find_for(current_user, arg, *args)
        return nil if current_user.nil?
        resource = find_by arg, args
        return nil if resource.nil?
        return nil unless resource.can_view?(current_user)
        resource
      end

      def find_for_edit(current_user, arg, *args)
        return nil if current_user.nil?
        resource = find_for(current_user, arg, args)
        return nil if resource.nil?
        resource.can_edit?(current_user) ? resource : nil
      end

      def find_for_delete(current_user, arg, *args)
        return nil if current_user.nil?
        resource = find_for(current_user, arg, args)
        return nil if resource.nil?
        resource.can_delete?(current_user) ? resource : nil
      end

      def can_create?(current_user)
        return false if current_user.nil?
        current_user.is_admin || current_user.active
      end

    end

    def is_resource_owner?(current_user)
      current_user == user
    end

    def can_view?(current_user)
      return false if current_user.nil?
      current_user == user || current_user.is_admin
    end

    def can_edit?(current_user)
      can_view? current_user
    end

    def can_delete?(current_user)
      can_edit? current_user
    end

    # Make changes to collaborators
    def can_administer?(current_user)
      current_user.is_admin || user == current_user
    end

  end
end
