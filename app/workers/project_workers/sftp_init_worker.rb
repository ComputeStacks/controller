module ProjectWorkers
  ##
  # Ensure SFTP containers are present
  class SftpInitWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(project_id, event_id)
      project = GlobalID::Locator.locate project_id
      event = GlobalID::Locator.locate event_id

      event.start!
      sftp_prov = ProvisionServices::SftpProvisioner.new(project, event)
      if sftp_prov.perform
        sftp_builder = DeployServices::DeployProjectService.new(project, event)
        if sftp_builder.perform
          event.done!
        else
          event.event_details.create!(
            data: sftp_builder.errors.join("\n\n"),
            event_code: '6810c5d1c32b9d46'
          )
          event.fail! 'Error Building Containers'
        end
      else
        event.event_details.create!(
          data: sftp_prov.errors.join("\n\n"),
          event_code: '74e18fa9f2e42605'
        )
        event.fail! 'Error Selecting Containers'
      end
      event.done! if event.running?
    rescue ActiveRecord::RecordNotFound
      return
    rescue => e
      user = nil
      if defined?(event) && event
        event.event_details.create!(
          data: e.message,
          event_code: '0d0be20f7ff9768d'
        )
        event.fail! e.message
      end
      ExceptionAlertService.new(e, '0d0be20f7ff9768d', user).perform
    end

  end
end
