module ProvisionServices
  # Provision private load balancers for a given service
  #
  class IngressControllerProvisioner

    attr_accessor :service,
                  :load_balancers, # The ones we are creating here
                  :project,
                  :event,
                  :errors

    def initialize(service, event)
      self.service = service
      self.event = event
      self.project = service.deployment if service&.deployment
      self.errors = []
      self.load_balancers = []
    end

    def perform
      return false unless valid?

      # Ensure it's not already provisioned!
      return true if project.services.where("labels @> ?", { load_balancer_for: service.id }.to_json).exists?

      # 1. Determine which load balancers we need to provision
      requests = []
      service.container_image.ingress_params.where.not(load_balancer_rule: nil).each do |i|
        lb_image = i.load_balancer_rule.container_image
        next if lb_image.nil?
        next if lb_image.user && (deployment.user != lb_image.user) # Permission to use this LB!
        requests << lb_image.id unless requests.include?(lb_image.id)
      end

      # 2. Provision each LB
      requests.each do |k|
        lb_image = ContainerImage.find_by(id: k)
        next if lb_image.nil?
        provision_load_balancer lb_image
      end
      errors.empty?
    end

    private

    def provision_load_balancer(image)
      lb_name = NamesGenerator.name project.id
      variant = image.image_variants.default.first
      if variant.nil?
        errors << "Missing image variant for image #{image.id}"
        return
      end
      lb_service = project.services.new(
        image_variant: variant,
        is_load_balancer: true,
        name: lb_name,
        label: lb_name,
        cpu: 1,
        memory: 1024,
        region: service.region,
        command: image.command,
        labels: { load_balancer_for: service.id }
      )

      unless lb_service.save
        lb_service.errors.full_messages.each do |e|
          errors << e
        end
        return
      end

      load_balancers << lb_service

      # Generate Service Config for LB
      return unless lb_service.gen_settings_config!(event)
      return unless lb_service.gen_ingress_rules!(event)

      # Generate Container
      lb_container = ProvisionServices::ContainerProvisioner.new(lb_service)
      unless lb_container.perform
        lb_container.errors.each do |i|
          errors << i
        end
      end
      NetworkWorkers::ServicePolicyWorker.perform_async lb_service.id
    end

    def valid?
      return false if service.nil?
      return false if project.nil?
      return false if event.nil?
      true
    end

  end
end
