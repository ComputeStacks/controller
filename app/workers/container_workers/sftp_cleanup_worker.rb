module ContainerWorkers
  class SftpCleanupWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform
      project_empty_check = []
      Deployment::Sftp.trashable.each do |i|
        next unless i.node.online?
        audit = if i.deployment
          Audit.find_by(event: 'deleted', rel_id: i.deployment.id, rel_model: 'Deployment')
        else
          nil
        end
        project_empty_check << i.deployment if i.deployment && project_empty_check.include?(i.deployment)
        audit = Audit.create_from_object!(i, 'deleted', '127.0.0.1') if audit.nil?
        i.delete_now!(audit)
        i.destroy
      end

      ##
      # Trigger ProjectEmptyCheck
      project_empty_check.each do |project|
        if project.services.empty? && project.status == 'deleting'
          project.destroy
        end
      end
    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue => e
      ExceptionAlertService.new(e, 'c0c0dc664fae7f38').perform
    end

  end
end
