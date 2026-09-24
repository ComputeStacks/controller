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
      :volume_clones,
      :errors

    def initialize(project, event)
      self.project = project
      self.event = event
      self.volume_clones = []
      self.errors = []
    end

    def perform
      if project.region.has_clustered_networking?
        # Apply Project Service Policy
        NetworkWorkers::ProjectPolicyWorker.perform_async project.global_id
      end

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
        PowerCycleContainerService.new(container, "build", event.audit).perform
      end

      # For SFTP containers, we will either rebuild or build depending on current state
      project.sftp_containers.active.each do |container|
        j = PowerCycleContainerService.new(container, container.built? ? "rebuild" : "build", event.audit)
        j.delay = 30.seconds
        j.perform
      end

      # Reload Load Balancers
      project.load_balancers.each do |lb|
        LoadBalancerServices::DeployConfigService.new(lb).perform
      end

      ProjectServices::StoreMetadata.new(project).perform

      # Schedule volume clones.
      #
      # This used to run the clones INLINE and block on them: a Timeout+sleep loop per volume,
      # budgeted at up to ~46 minutes each, serially, inside ProcessOrderWorker on the `default`
      # queue. supervisord sends stopsignal=KILL, so any deploy annihilated that job and left
      # the order wedged in `processing` forever. Now we only write durable VolumeCloneJob rows
      # and hand them to the sweeper — the order finishes in milliseconds and the restores run
      # asynchronously with their own per-volume events.
      #
      # NB `errors.concat`, not `errors + ...`. The old code's `errors + cv.errors` discarded its
      # own result, and the single branch that populated cv.errors was exactly the one it threw
      # away, so a volume that was never cloned still completed the order green.
      unless volume_clones.empty?
        enqueue = VolumeServices::EnqueueCloneService.new(project, event, volume_clones)
        enqueue.perform
        errors.concat enqueue.errors
      end

      # Clear project icon cache
      project.image_icons true

      errors.empty?
    end
  end
end
