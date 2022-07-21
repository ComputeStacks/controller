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
      clean_ingress_rules
      pause_subscriptions
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

    def clean_ingress_rules
      service.ingress_rules.each do |i|
        i.skip_policy_updates = true
        i.destroy
      end
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
