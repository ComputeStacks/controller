module ProvisionServices
  ##
  # Build Container
  #
  # @!attribute service
  #   @return [Deployment::ContainerService]
  # @!attribute container
  #   @return [Deployment::Container]
  # @!attribute node
  #   @return [Node]
  # @!attribute errors
  #   @return [Array]
  class ContainerProvisioner
    attr_accessor :service,
      :container,
      :node,
      :errors

    # @param [Deployment::ContainerService] service
    def initialize(service)
      self.service = service
      self.node = nil
      self.container = nil
      self.errors = []
    end

    # @return [Boolean]
    def perform
      return false unless valid?
      set_node!
      if node.nil?
        errors << "Unable to locate node."
        return false
      end
      return false unless build_container!
      return true if service.is_load_balancer # TEMPORARY
      init_subscription!
    end

    private

    # @return [Boolean]
    def init_subscription!
      return true if service.container_image.is_free
      if container.nil?
        errors << "Missing container obj for #{service.name}, skipping..."
        return false
      end
      return true if container.subscription
      if service.initial_subscription
        container.subscription = service.initial_subscription
        unless container.save
          errors << "Error saving subscription: #{container.errors.full_messages.join(" ")}"
          return false
        end
        unless service.update_attribute(:initial_subscription, nil)
          errors << "Error saving service subscription: #{service.errors.full_messages.join(" ")}"
        end
        s = container.subscription
        unless s.update_attribute(:label, container.name)
          errors << "Error updating subscription: #{s.errors.full_messages.join(" ")}"
        end
      else
        example_container = service.containers.where.not(subscription: nil).first
        if example_container.nil?
          errors << "Error! Unable to locate subscription data."
          return false
        end
        s = example_container.subscription.dup
        s.active = false
        s.label = container.name
        unless s.save
          errors << "Error creating subscription"
          errors << s.errors.full_messages.join(" ")
          return false
        end
        example_container.subscription.subscription_products.each do |sp|
          s.subscription_products.create!(product: sp.product, allow_nil_phase: true)
        end
        unless container.update_attribute(:subscription, s)
          errors << "Error saving container #{container.name} subscription: #{container.errors.full_messages.join(" ")}"
        end
      end
      errors.empty?
    end

    def set_node!
      return unless node.nil?
      # For clustered storage, or no volumes, pick any node past on normal logic
      self.node = if service.volumes.empty? || service.region.has_clustered_storage?
        service.region.find_node service.package_for_node
      elsif service.volumes.first.nodes.empty? # check that our volumes are assigned a node.
        if service.nodes.empty? # finally, fall back to normal node assignment if we have no nodes linked to this service.
          service.region.find_node service.package_for_node
        else # with no volumes having nodes, then use an existing node for this service
          service.nodes.first
        end
      else # no clustered storage and has volumes, pick the node that has the volume
        service.volumes.first.nodes.first
      end
    end

    # @return [Boolean]
    def build_container!
      if service.package_for_node.nil?
        errors << "missing service package, unable to find node."
        return false
      end
      # cpu/memory are set HERE, not only in the assignment below, because nothing wraps
      # provisioning in a transaction: a row created blank is committed and visible to
      # any concurrent order's capacity sum until the save at the end of this method, and
      # permanently if that save fails (rollback! only destroys containers recorded after
      # a successful build). Those columns are what the node enforces and what capacity is
      # summed from, so a blank one is a container that counts as nothing.
      self.container = service.containers.create!(cpu: service.cpu, memory: service.memory) # Create to grab the ID
      unless container
        errors << "Failed to generate init container."
        return false
      end
      container.name = "#{service.name}-#{container.id}"
      container.node = node
      container.cpu = service.cpu
      container.memory = service.memory
      unless container.save
        errors << "Failed to generate container: #{container.errors.full_messages.join(" ")}"
        return false
      end
      true
    end

    # @return [Boolean]
    def valid?
      unless service.user.can_order_containers? 1
        errors << "User is over quota, unable to provision containers"
      end
      if service.region.nil?
        errors << "Service is missing a region"
      end
      errors.empty?
    end
  end
end
