module ContainerServices
  ##
  # AutoScale a container service
  #
  # This service will scale a container service to the next package.
  # Selection of the next package will be based on the resource alert that triggered this process,
  # so either memory or cpu.
  #
  # @!attribute service
  #   @return [Deployment::ContainerService]
  # @!attribute resource_kind
  #   @return [String]
  # @!attribute event
  #   @return [EventLog]
  class AutoScaleService

    attr_accessor :service,
                  :resource_kind,
                  :event

    # @!attribute [Deployment::ContainerService] service
    # @!attribute [String] resource_kind memory or cpu
    def initialize(service, resource_kind)
      self.service = service
      self.resource_kind = resource_kind
      self.event = nil
    end

    # @return [Boolean]
    def perform
      self.event = build_event
      unless service.auto_scale
        event.cancel! "AutoScale is disabled"
        return false
      end
      package = new_package
      package.nil? ? perform_scale! : perform_resize!(package)
    ensure
      event.done! if event.active?
    end

    private

    def perform_resize!(package)
      return false unless can_resize?
      service.containers.each do |container|
        event.containers << container
        prov = ProvisionServices::ContainerResizeProvisioner.new(container, event, package)
        unless prov.perform
          event.event_details.create!(
            data: "Failed to resize container #{container.name}",
            event_code: '2557107aec1f048b'
          )
        end
      end
      if event.event_details.empty?
        event.event_details.create!(
          data: "Successfully scaled service to package #{package.product.label}",
          event_code: '4cc8457a85fbf277'
        )
        true
      else
        event.fail! 'Failed to resize container package'
        false
      end
    end

    def perform_scale!
      return false unless can_scale?
      prov = ProvisionServices::ScaleServiceProvisioner.new(service, event, service.containers.count + 1)
      if prov.perform
        event.event_details.create!(
          data: "Successfully scaled service to #{prov.qty} containers",
          event_code: 'fcc4ed0f3950d9fd'
        )
        true
      else
        event.event_details.create!(
          data: "Failed to scale service to #{prov.qty} containers",
          event_code: '608f07c22d9d11be'
        )
        event.fail! 'Failed to scale service'
        false
      end
    end

    # @return [EventLog]
    def build_event
      a = Audit.create_from_object!(service, 'updated', '127.0.0.1')
      e = EventLog.create!(
        locale: 'service.autoscale',
        locale_keys: { 'label' => service.label },
        event_code: '9f30297365cd6d72',
        status: 'running',
        audit: a
      )
      e.deployments << service.deployment
      e.container_services << service
      e
    end

    ##
    # Locate next package given the current resource constraint
    #
    # Will also use the service max price as a constraint.
    def new_package
      cur_mem = service.containers.first.memory
      cur_cpu = service.containers.first.cpu

      # In a memory alert situation, find the next largest package by memory.
      # CPU is allowed to meet or exceed current usage, but not be less.
      #
      # Given a CPU alert, find the next largest CPU package.
      # Memory is allowed to meet or exceed current value, but not be less.
      package = if resource_kind == 'memory'
                  BillingPackage.where(Arel.sql(%Q(cpu >= #{cur_cpu} AND memory > #{cur_mem}))).order(memory: :asc)[0]
                else
                  BillingPackage.where(Arel.sql(%Q(cpu > #{cur_cpu} AND memory >= #{cur_mem}))).order(cpu: :asc)[0]
                end
      return nil if package.nil?
      if service.auto_scale_max > 0
        price_obj = package.product.price_lookup service.user, service.region, service.containers.count
        if price_obj && price_obj.price > service.auto_scale_max
          event.event_details.create!(
            data: "Unable to locate package under current price restriction",
            event_code: 'b192b7fcb4e94b0c'
          )
          event.cancel! "Resize would exceed max price"
          return nil
        end
      end
      package
    end

    ##
    # Can we scale horizontally?
    #
    # @return [Boolean]
    def can_scale?
      unless service.auto_scale_horizontal
        event.event_details.create!(
          data: "Horizontal auto-scaling is disabled",
          event_code: 'eae7a20c7f5e2036'
        )
        event.cancel! 'Horizontal Scaling Disabled'
        return false
      end
      unless service.can_scale?
        event.event_details.create!(
          data: "Image is not allowed to horizontally scale.",
          event_code: '66b53b86882bd194'
        )
        event.cancel! 'Unable to scale'
        return false
      end
      # Check if adding a container will increase the price above `service.auto_scale_max`.
      if service.auto_scale_max > 0
        base_price = 0.0
        current_plan = service.subscriptions.inject(0) do |sum, i|
          next if i.package_subscription.nil?
          next if i.package_subscription.current_price&.price.nil?
          base_price = i.package_subscription.current_price.price
          sum += base_price
          sum
        end
        if current_plan.nil?
          event.event_details.create!(
            data: "Unable to scale, current package is not in your billing plan. Please manually resize to a current valid plan.",
            event_code: '7d600528d5c15c6e'
          )
          event.cancel! "Package outside of billing plan"
        elsif current_plan + base_price > service.auto_scale_max
          event.event_details.create!(
            data: "Additional container would be greater than the max allowable price for this service.",
            event_code: '20b5238a7e665c27'
          )
          event.cancel! "Scale would exceed max price"
        end
        return false
      end
      true
    end

    ##
    # Can we scale by resize?
    #
    # @return [Boolean]
    def can_resize?
      if service.containers.migrating.exists?
        c = service.containers.migrating.map { |i| i.name }
        event.event_details.create!(
          data: "Unable to resize the following containers due to a current migration job:\n\n#{c.join("\n")}",
          event_code: 'f9db242cae3af0e0'
        )
        event.cancel! "Container operation in progress"
        return false
      end
      if service.nodes.offline.exists?
        event.event_details.create!(
          data: "Unable to scale due to offline nodes",
          event_code: 'becb612d14805ade'
        )
        event.cancel! "Nodes are unavailable"
        return false
      end
      true
    end

  end
end
