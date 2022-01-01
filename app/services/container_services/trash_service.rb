module ContainerServices
  ##
  # Delete a single container service
  #
  # @!attribute event
  #   @return [EventLog]
  # @!attribute service
  #   @return [Deployment::ContainerService]
  #
  class TrashService

    attr_accessor :service,
                  :event

    # @param [Deployment::ContainerService] service
    # @param [EventLog] event
    def initialize(service, event)
      self.service = service
      self.event = event
    end

    # @return [Boolean]
    def perform
      unless clean_load_balancer
        event.event_details.create!(
          data: "Error cleaning load balancer, halting destruction.",
          event_code: "0a2e8546f1644624"
        )
        return false
      end
      clean_nat_ports # Will continue on failure
      pause_subscriptions
      clean_net_policy
      return false unless delete_containers
      return true if service.destroy
      event.event_details.create!(
        data: "Error removing service\n\n#{service.errors.full_messages.join(' ')}",
        event_code: 'b12c483efb174c42'
      )
      false
    end

    private

    ##
    # If using custom load balancer, delete that now.
    def clean_load_balancer
      lb_service = service.current_load_balancer
      if lb_service.is_a? Deployment::ContainerService
        event.container_services << lb_service
        return ContainerServices::TrashService.new(lb_service, event).perform
      end
      true
    end

    # Pause Subscriptions
    #
    # Proactively stops billing in case
    # there is an error deleting the container.
    #
    # Containers will save their details and also flag
    # the subscription has halted during their deletion.
    def pause_subscriptions
      service.subscriptions.each do |sub|
        sub.current_audit = event.audit
        sub.pause!
      end
    end

    # @return [Boolean]
    def clean_nat_ports
      success = true
      service.ingress_rules.each do |i|
        unless i.public_port.zero?
          unless i.toggle_nat!
            success = false
            event.event_details.create!(
              data: i.errors.full_messages.join(' '),
              event_code: 'a861fc0361cc160d'
            )
          end
        end
      end
      success
    end

    def clean_net_policy
      NetworkWorkers::TrashPolicyWorker.perform_async service.region.id, service.name
    end

    # @return [Boolean]
    def delete_containers
      success = true
      service.containers.each do |container|
        unless ContainerServices::TrashContainer.new(container, event).perform
          success = false
        end
      end
      success
    end

  end
end
