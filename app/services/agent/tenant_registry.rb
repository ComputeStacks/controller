module Agent
  ##
  # Where a project's agent tenant exists (`agent_tenants`), and the tombstone that
  # stops it ever being recreated once the project is being trashed.
  #
  # A row is written on every successful provision (Agent::Client#provision_tenant!,
  # including put_managed's self-heal). Project trash tombstones the rows FIRST, before
  # any HTTP call, then deprovisions every region it knows of; a successful deprovision
  # deletes every pending sync for that (region, project), but the tombstone itself
  # outlives it while the Project row exists. TrashProject forgets the rows once the
  # project is destroyed, and lifts the tombstone if the trash aborts.
  #
  # `deleting?` is consulted by Agent::PendingSync.record!, by replay, and by the live
  # managed writers, so nothing re-provisions a tenant that is being torn down.
  module TenantRegistry
    module_function

    # @param project_id [Integer]
    # @param region_id [Integer]
    def provisioned!(project_id, region_id)
      return if project_id.nil? || region_id.nil?
      now = Time.current
      # Never clears deleting_at: a tombstone outranks a late provision.
      AgentTenant.upsert(
        {project_id: project_id, region_id: region_id, provisioned_at: now, created_at: now, updated_at: now},
        unique_by: [:project_id, :region_id],
        update_only: [:provisioned_at]
      )
    rescue => e
      ExceptionAlertService.new(e, "4f0e7c2a9d813b65").perform
      nil
    end

    # Tombstone the project in each region (creating rows for regions the registry
    # didn't know about), so `deleting?` holds from here on.
    # @param project_id [Integer]
    # @param region_ids [Array<Integer>]
    def tombstone!(project_id, region_ids)
      now = Time.current
      AgentTenant.where(project_id: project_id, deleting_at: nil).update_all(deleting_at: now, updated_at: now)
      rows = region_ids.compact.uniq.map do |rid|
        {project_id: project_id, region_id: rid, deleting_at: now, created_at: now, updated_at: now}
      end
      AgentTenant.insert_all(rows, unique_by: [:project_id, :region_id]) if rows.any?
    end

    # True once the project is being trashed, or when the Project row is gone.
    # @param project_id [Integer]
    def deleting?(project_id)
      return true if project_id.nil?
      AgentTenant.where(project_id: project_id).where.not(deleting_at: nil).exists? ||
        !Deployment.exists?(project_id)
    end

    # The deprovision of (project, region) succeeded: drop every agent write still
    # pending for it. The registry row (the tombstone) goes too only once the Project
    # row is gone; while the project still exists the trash may yet abort, and until
    # then the tombstone must keep `deleting?` true.
    def deprovisioned!(project_id, region_id)
      ActiveRecord::Base.transaction do
        AgentPendingSync.where(project_id: project_id, region_id: region_id).delete_all
        unless Deployment.exists?(project_id)
          AgentTenant.where(project_id: project_id, region_id: region_id).delete_all
        end
      end
    end

    # The project was destroyed: forget its tenant everywhere, along with every pending
    # write except a `tenant_delete` still owed to an agent.
    def forget!(project_id)
      ActiveRecord::Base.transaction do
        AgentTenant.where(project_id: project_id).delete_all
        AgentPendingSync.where(project_id: project_id).where.not(kind: "tenant_delete").delete_all
      end
    end

    # The trash aborted after tombstoning: the project lives on. Lift the tombstone,
    # cancel its pending deprovisions, and mark the tenant and its managed blobs dirty
    # in every region, so replay rebuilds what the trash may already have deprovisioned
    # (writes skipped while it was tombstoned were never recorded).
    #
    # A no-op once the Project row is gone: another trash run destroyed it, and its
    # owed `tenant_delete` rows must survive.
    def lift_tombstone!(project_id)
      project = Deployment.find_by(id: project_id)
      return if project.nil?

      region_ids = ActiveRecord::Base.transaction do
        AgentTenant.where(project_id: project_id).where.not(deleting_at: nil).update_all(deleting_at: nil, updated_at: Time.current)
        AgentPendingSync.where(project_id: project_id, kind: "tenant_delete").delete_all
        AgentTenant.where(project_id: project_id).pluck(:region_id)
      end

      region_ids.each do |rid|
        %w[tenant managed_metadata managed_ssh_keys].each do |kind|
          PendingSync.record!(region: rid, project: project_id, kind: kind, error: "rebuild after aborted project trash")
        end
      end
      project.sftp_containers.each do |sftp|
        rid = sftp.region&.id
        next unless rid && region_ids.include?(rid)
        PendingSync.record!(region: rid, project: project_id, kind: "managed_sftp_host_keys", key: sftp.name, error: "rebuild after aborted project trash")
      end
    end

    # @return [Array<Integer>] the regions the registry holds for this project
    def region_ids(project_id)
      AgentTenant.where(project_id: project_id).pluck(:region_id)
    end
  end
end
