module ProjectWorkers
  ##
  # Update project cache
  #
  # Should run when:
  # * ProvisionService
  # * ResizeService
  # * ScaleService
  # * TrashService
  #
  class ProjectCacheWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'low'

    def perform(project_id = nil)
      if project_id.blank?
        Deployment.all.each do |d|
          project_data d
        end
      else
        d = Deployment.find_by(id: project_id)
        return false if d.nil?
        project_data d
      end
    end

    private

    def project_data(project)
      project.run_rate true
      project.current_storage true
      project.image_icons true
    end

  end
end
