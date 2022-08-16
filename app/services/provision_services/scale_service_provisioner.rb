module ProvisionServices
  ##
  # Scale a service to desired number of containers
  #
  # @!attribute container_service
  #   @return [Deployment::ContainerService]
  # @!attribute event
  #   @return [EventLog]
  # @!attribute qty
  #   @return [Integer]
  class ScaleServiceProvisioner

    attr_accessor :container_service,
                  :event,
                  :qty

    # @param [Deployment::ContainerService] service
    # @param [EventLog] event
    # @param [Integer] qty
    def initialize(service, event, qty)
      self.container_service = service
      self.event = event
      self.qty = qty.to_i # anything other than an int will be 0.
    end

    # @return [Boolean]
    def perform
      return false unless valid?
      current_count = container_service.containers.count
      if qty > current_count # Add Containers
        1.upto(qty - current_count) do
          new_container = ProvisionServices::ContainerProvisioner.new(container_service)
          unless new_container.perform || new_container.container
            if new_container.errors.empty?
              event.event_details.create!(
                data: "Fatal error while provisioning container",
                event_code: 'd8b7a1905c40c7e7'
              )
            else
              event.event_details.create!(
                data: new_container.errors.join("\n\n"),
                event_code: 'c82253e070f96a83'
              )
            end
            event.fail! 'Error building container'
            return false
          end
          event.event_details.create!(
            data: "Created container: #{new_container.container.name}",
            event_code: 'b2059e7d695115be'
          )
          ContainerWorkers::ProvisionWorker.perform_async new_container.container.to_global_id.to_s, event.to_global_id.to_s
        end
      else # Remove Containers
        container_service.containers.limit(current_count - qty).order(:created_at).each do |container|
          trash_container = ContainerServices::TrashContainer.new(container, event)
          event.fail! 'Error removing containers' unless trash_container.perform
        end
      end
      reload_load_balancers
      ProjectServices::StoreMetadata.new(container_service.deployment).perform
      !event.failed?
    end

    private

    # @return [Boolean]
    def valid?

      unless container_service.can_scale?
        event.event_details.create!(
          data: "Service is not eligibale to scale",
          event_code: "b92040241f7db4e0"
        )
        event.fail! "Scaling not allowed"
        return false
      end

      # Ensure QTY is a positive integer greater than 0.
      if qty < 1
        event.event_details.create!(
          data: "Expected #{qty} to be 1 or greater.",
          event_code: '13f3b157a1a84b44'
        )
        event.fail! 'Invalid Parameters'
        return false
      end

      # Ensure QTY is different than current count
      current_count = container_service.containers.count
      if current_count == qty
        event.cancel! 'No change required'
        return false
      end

      # Ensure user has permission to add containers
      current_count = container_service.containers.count
      if qty > current_count
        add_count = qty - current_count
        unless container_service.user.can_order_containers? add_count
          event.fail! 'User over quota'
          return false
        end
      end
      true
    end

    ##
    # Reload both global and internal LBs
    def reload_load_balancers
      # Internal LBs
      container_service.internal_load_balancers.each do |service|
        service.containers.each do |container|
          PowerCycleContainerService.new(container, 'restart', current_audit).perform
        end
      end

      # Global LB
      if container_service.load_balancer
        LoadBalancerServices::DeployConfigService.new(container_service.load_balancer).perform
      end
    end

  end
end
