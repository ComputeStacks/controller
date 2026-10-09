module ProjectServices
  class TrashProject
    attr_accessor :project,
      :event,
      :user

    def initialize(project, event)
      self.project = project
      self.event = event
      if event.audit
        self.user = event.audit&.user
        self.project.current_event = event
      end
    end

    # @return [Boolean]
    def perform
      return false unless valid?
      destroyed = false
      ActiveRecord::Base.uncached do
        clean_metadata_tenant!
        if project.private_network
          # Immediately remove our link to it.
          #
          # `active: true` alongside the detach: the allocation pool is "inactive AND no
          # deployment", so detaching a row that is inactive hands it straight to the next
          # project while a docker network may still carry its name and subnet. Marking it
          # active means "unconfirmed, do not reuse" and puts it in `child_networks.active`,
          # which is the set PrivateNetCleanupWorker retries -- it removes the network from
          # the node and clears the flag once every node confirms it gone. Not trashed inline:
          # this runs before the containers are destroyed, so the network still has addresses
          # in use and TrashBridgeNetworkService would decline anyway.
          project.private_network.update deployment_id: nil, active: true
        else
          clean_network_policy!
        end
        trash_sftp_containers! # failure can be ignored
        return false unless trash_services!
        project.reload
        if project.destroy
          destroyed = true
          forget_metadata_tenant!
          return true
        end
      end
      event.event_details.create!(
        event_code: "8a1349f61c2a2dcb",
        data: if project.errors.full_messages.empty?
                "Unknown fatal error prevented this project from being deleted."
              else
                project.errors.full_messages.join("\n")
              end
      )
      false
    ensure
      # Every abort after the tombstone (a false return or an exception) leaves the
      # project alive: it must not stay `deleting?`.
      lift_metadata_tombstone! if @tombstoned && !destroyed
    end

    private

    def valid?
      unless user
        event.event_details.create!(
          event_code: "c1302d4837f367e6",
          data: "User performing action is missing. Required in order to delete this resource."
        )
        return false
      end
      project.can_delete? user
    end

    def clean_network_policy!
      project.regions.all.each do |i|
        NetworkWorkers::TrashPolicyWorker.perform_async i.id, project.token
      end
    end

    # Deprovision the project's agent tenant everywhere it may exist.
    #
    # 1. Tombstone FIRST, before any HTTP call: from here on nothing (live managed
    #    writers, put_managed's self-heal, replay) may provision this tenant again.
    # 2. Every region in (tenant registry ∪ project.regions ∪ sftp regions). The
    #    registry covers regions the project no longer has services in.
    # 3. A success drops its pending syncs there (the tombstone stays until the
    #    project is destroyed); a failure is recorded as a pending `tenant_delete`
    #    and replayed, even after the Project row is gone.
    #
    # #perform forgets the registry rows once the project is destroyed, or lifts the
    # tombstone if the trash aborts.
    def clean_metadata_tenant!
      region_ids = metadata_tenant_region_ids
      @tombstoned = true # set first: a tombstone! that raised partway is still lifted
      Agent::TenantRegistry.tombstone!(project.id, region_ids)
      Region.where(id: region_ids).each do |region|
        error = nil
        ok = begin
          Agent::Client.for_project_id(project.id, region: region).deprovision_tenant!
        rescue Agent::Client::NotReady => e
          error = e
          false
        end
        if ok
          Agent::TenantRegistry.deprovisioned!(project.id, region.id)
        else
          Agent::PendingSync.record!(region: region, project: project.id, kind: "tenant_delete",
            error: error || "agent did not accept the tenant deprovision")
        end
      end
    end

    def forget_metadata_tenant!
      Agent::TenantRegistry.forget!(project.id)
    rescue => e
      # The Project row is gone, so `deleting?` holds regardless.
      ExceptionAlertService.new(e, "b2e61f0d9c4a7358").perform
    end

    def lift_metadata_tombstone!
      Agent::TenantRegistry.lift_tombstone!(project.id)
    rescue => e
      ExceptionAlertService.new(e, "6d0a3c8e15f9b247").perform
    end

    # @return [Array<Integer>]
    def metadata_tenant_region_ids
      sftp_region_ids = Node.where(id: project.sftp_containers.select(:node_id)).distinct.pluck(:region_id)
      (Agent::TenantRegistry.region_ids(project.id) + project.regions.pluck(:id) + sftp_region_ids).compact.uniq
    end

    def trash_sftp_containers!
      project.sftp_containers.each do |container|
        ContainerServices::TrashContainer.new(container, event).perform
      end
    end

    # @return [Boolean]
    def trash_services!
      success = true
      project.services.each do |service|
        unless ContainerServices::TrashService.new(service, event).perform
          success = false
        end
      end
      success
    end
  end
end
