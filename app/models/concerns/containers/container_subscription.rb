module Containers
  module ContainerSubscription
    extend ActiveSupport::Concern

    included do
      before_destroy :save_subscription, prepend: true
    end

    # Called from HealthCheck.
    #
    # Ensures billing status is correct based on it's state.
    #
    def update_subscription_by_status!(status)
      return if user.user_group.bill_offline ## bill_offline
      return unless %w(running exited stopped).include?(status)
      return if subscription&.package_subscription.nil? # sanity check
      return unless subscription.active # if the entire sub is paused, then dont modify it.
      if status == 'running'
        subscription.package_subscription.unpause!
      else
        subscription.package_subscription.pause!
      end
    end

    def package
      return nil if subscription&.package.nil?
      subscription.package
    end

    # Package used to place container
    def package_for_node
      return BillingPackage.new(cpu: 1, memory: 512) if subscription.nil? || subscription.package.nil?
      subscription.package
    end

    def package_has_swap?
      return false if subscription&.package.nil?
      !subscription&.package.memory_swap.nil?
    end

    def init_subscription!
      return true if container_image.is_free
      return false if service.nil?
      if subscription.nil?
        base_subscription = service.containers.where("subscription_id is not null").empty? ? service.initial_subscription : service.containers.where("subscription_id is not null").first&.subscription
        if base_subscription.container
          new_sub = Subscription.create!(
              user_id: base_subscription.user_id,
              label: name,
              external_id: base_subscription.external_id,
              details: base_subscription.details
          )
          update_attribute :subscription, new_sub
          base_subscription.subscription_products.each do |sp|
            new_sub.subscription_products.create!(
                product: sp.product,
                external_id: sp.external_id,
                phase_type: sp.phase_type,
                start_on: Time.now
            )
          end
        else
          # Grab ownership of the subscription
          base_subscription.update(
                               active: true,
                               container: self
          )
          service.update_attribute :initial_subscription, nil
        end
      else
        subscription.update(active: true) unless subscription.active
      end # END if subscription.nil?
    end # END init_subscription!

    private

    def save_subscription
      BillingUsageServices::CollectUsageService.new(self).perform
      if subscription && user
        # If it's already inactive, then this would have already been created.
        if subscription.active
          BillingEvent.create!(
            subscription_id: subscription.id,
            from_status: true,
            to_status: false,
            rel_id: id,
            rel_model: 'Deployment::Container'
          )
          subscription.subscription_products.each do |i|
            i.update_attribute :active, false
          end
        end
        subscription.update(
          active: false,
          details: {
            'name' => name,
            'label' => label,
            'container_service_id' => container_service_id,
            'deployment_id' => deployment.id,
            'deployment' => deployment.name,
            'user_id' => user.id,
            'region' => region.name
          }
        )
      end
    end

  end
end
