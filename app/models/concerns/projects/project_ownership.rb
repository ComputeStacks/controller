module Projects
  module ProjectOwnership
    extend ActiveSupport::Concern

    included do
      before_update :migrate_project_ownership
    end

    # Requires: current_audit
    def migrate_project_ownership
      return unless user_id_changed?
      errors.add(:base, "Missing audit object") unless current_audit
      errors.add(:base, "Invalid permission") unless current_audit&.user&.is_admin

      throw(:abort) unless errors.empty?

      # previous_user_id = user_id_was
      # existing_user = User.find_by(id: user_id_was)

      ##
      # Check permission

      # Suspended?
      errors.add(:user_id, "new user is currently suspended") unless user.active

      # Container quota
      errors.add(:user_id, "new user would exceed their container quota") unless user.can_order_containers?(deployed_containers.count)

      # container images
      container_images.each do |image|
        next if user.is_admin # Admin's are allowed to see other user's image.
        next if image.user.nil?
        unless image.can_view?(user)
          errors.add(:user_id, "does not have access to #{image.label}")
        end
        if image.container_registry && !image.container_registry.can_view?(user)
          errors.add(:user_id, "does not have access to registry #{image.container_registry.label}")
        end
      end

      # Regions
      regions.each do |r|
        unless user.user_group.regions.include?(r)
          errors.add(:user_id, "user does not have access to region #{r.name}")
        end
      end

      throw(:abort) unless errors.empty?

      # Migrate Subscriptions
      sub_state = []
      deployed_containers.each do |container|
        next if container.subscription.nil?
        i_state = {
          container: container.id,
          subscription: container.subscription.id,
          new_subscription: nil
        }
        sub_state << i_state
        new_sub = container.subscription.dup
        new_sub.user_id = user.id
        unless new_sub.save
          # rollback
          errors.add(:base, "subscription: #{new_sub.errors&.full_messages}")
          return rollback_new_owner!(sub_state)
          # create event to record error message?
        end
        i_state[:new_subscription] = new_sub.id
        container.subscription.subscription_products.each do |p|
          new_p = p.dup
          new_p.subscription = new_sub
          unless new_p.save
            # rollback
            errors.add(:base, "subscription product: #{new_p.errors&.full_messages}")
            return rollback_new_owner!(sub_state)
            # create event to record error message?
          end
        end
        container.subscription.pause!
        container.update_attribute :subscription, new_sub
      end

      volumes.each do |vol|
        vol.current_audit = current_audit
        sub_state << {
          volume: vol.id,
          user: vol.user&.id
        }
        vol.skip_user_update = true # Otherwise it will update back to the deployment
        vol.user = user
        unless vol.save
          errors.add(:base, "volume: #{vol.errors&.full_messages}")
          return rollback_new_owner!(sub_state)
        end
      end

      domains.each do |d|
        d.current_audit = current_audit
        sub_state << {
          domain: d.id,
          user: d.user&.id
        }
        d.user = user
        unless d.save
          errors.add(:base, "domain: #{d.errors&.full_messages}")
          return rollback_new_owner!(sub_state)
        end
      end

      ProjectWorkers::RefreshMetadataWorker.perform_async id
      ProjectWorkers::RefreshMetadataSshWorker.perform_async id, current_audit&.id

    end

    def rollback_new_owner!(data = [])
      data.each do |i|
        if i[:volume]
          v = Volume.find_by(id: i[:volume])
          next if v.nil?
          next if i[:user].nil?
          u = User.find_by(id: i[:user])
          next if u.nil?
          # This is to avoid other validation errors that prevent the original save
          v.update_column :user_id, u.id
        elsif i[:domain]
          d = Deployment::ContainerDomain.find_by(id: i[:domain])
          next if d.nil?
          next if i[:user].nil?
          u = User.find_by(id: i[:user])
          next if u.nil?
          # This is to avoid other validation errors that prevent the original save
          d.update_column :user_id, u.id
        else
          c = Deployment::Container.find_by(id: i[:container])
          next if c.nil?
          old_sub = Subscription.find_by(id: i[:container])
          next if old_sub.nil?
          old_sub.unpause!
          c.update_attribute :subscription, old_sub
          new_sub = Subscription.find_by(id: i[:new_subscription])
          next if new_sub.nil?
          new_sub.destroy
        end
      end
      throw(:abort)
    end

  end
end
