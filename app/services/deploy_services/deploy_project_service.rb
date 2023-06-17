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

      # Clone Volumes
      volume_clones.each do |i|
        v = Volume.find_by(id: i[:vol_id])
        if v.nil?
          errors << "Volume #{i[:vol_id]} not found, unable to restore."
          next
        end
        cv = VolumeServices::CloneVolumeService.new(v, event)
        if i[:source_vol_id]
          sv = Volume.find_by id: i[:source_vol_id]
          if sv.nil?
            errors << "Source Volume #{i[:source_vol_id]} not found, unable to restore."
            next
          end
          cv.source_volume = sv
        else
          errors << "Missing source volume, unable to restore: #{i}"
          next
        end
        cv.source_snapshot = i[:source_snap] if i[:source_snap]
        unless cv.perform
          if cv.errors.empty?
            errors << "Fatal error restoring volume #{i[:vol_id]}"
          else
            errors + cv.errors
          end
        end
      end

      # Clear project icon cache
      project.image_icons true

      errors.empty?
    end

  end
end
