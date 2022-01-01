module DeployServices

  # DeployProjectService
  #
  # This will ensure all project resources are provisioned
  #
  # This should be run AFTER creating them locally in the database.
  #
  class DeployProjectService

    attr_accessor :project,
                  :event,
                  :errors

    def initialize(project, event)
      self.project = project
      self.event = event
      self.errors = []
    end

    def perform

      # Apply Project Service Policy
      NetworkWorkers::ProjectPolicyWorker.perform_async project.to_global_id.uri

      # Collect all the services that we need to deploy
      services = []
      containers = [] # Save us an extra call out to docker client to see if it's built.

      project.deployed_containers.active.each do |container|
        unless container.built?
          services << container.service unless services.include?(container.service)
          containers << container unless containers.include?(container)
        end
      end

      # Finalize requirements to build the service
      services.each do |s|
        unless s.init_link!
          errors << "Failed to find dependencies for #{s.name} (#{s.id})"
          next
        end
        unless s.gen_env_config!(event)
          errors << "Failed to generate environment for #{s.name} (#{s.id})"
          next
        end
      end

      return false unless errors.empty?

      # Build it!
      containers.each do |container|
        PowerCycleContainerService.new(container, 'build', event.audit).perform
      end

      # For SFTP containers, we will either rebuild or build depending on current state
      project.sftp_containers.active.each do |container|
        j = PowerCycleContainerService.new(container, container.built? ? 'rebuild' : 'build', event.audit)
        j.delay = 30.seconds
        j.perform
      end

      # Reload Load Balancers
      project.load_balancers.each do |lb|
        LoadBalancerServices::DeployConfigService.new(lb).perform
      end

      ProjectServices::StoreMetadata.new(project).perform

      errors.empty?
    end

  end
end
