module ProjectWorkers
  class RefreshMetadataWorker
    include Sidekiq::Worker

    sidekiq_options retry: false,
                    lock: :until_executed,
                    on_conflict: :reject

    def perform(project_id)
      project = Deployment.find_by id: project_id
      return if project.nil?
      ProjectServices::StoreMetadata.new(project).perform
    end

  end
end
