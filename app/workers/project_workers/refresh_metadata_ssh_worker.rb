module ProjectWorkers
  class RefreshMetadataSshWorker
    include Sidekiq::Worker

    sidekiq_options retry: false,
                    lock: :until_executed,
                    on_conflict: :reject,
                    lock_args_method: ->(args) { [ args.first ] } # We want to restrict by project, dont care about audit id!

    def perform(project_id, audit_id)
      project = Deployment.find_by id: project_id
      audit = Audit.find_by id: audit_id
      return if project.nil?
      ProjectServices::MetadataSshKeys.new(project).perform
      project.sftp_containers.each do |i|
        SftpServices::ReloadSshKeysService.new(i, audit).perform
      end
    end

  end
end
