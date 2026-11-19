module ProjectWorkers
  # After a service changes image variant: push fresh metadata, then have each
  # bastion re-select its default PHP from it.
  class RefreshMetadataPhpWorker
    include Sidekiq::Worker

    sidekiq_options retry: false,
      lock: :until_executed,
      on_conflict: :reject,
      lock_args_method: ->(args) { [args.first] }

    def perform(project_id, audit_id)
      project = Deployment.find_by id: project_id
      audit = Audit.find_by id: audit_id
      return if project.nil? || audit.nil?
      # Synchronous: the bastion reads the metadata we're about to push.
      return unless ProjectServices::StoreMetadata.new(project).perform
      # A stopped bastion selects PHP from the fresh metadata when it boots.
      project.sftp_containers.each do |i|
        next unless i.running?
        SftpServices::SelectPhpVersionService.new(i, audit).perform
      end
    end
  end
end
