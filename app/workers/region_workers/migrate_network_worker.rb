module RegionWorkers
  class MigrateNetworkWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(region_id, event_id)
      region = Region.find region_id
      event = EventLog.find event_id

      event.start!

      errors = []
      status = []

      region.deployments.where(private_network: { id: nil }).includes(:private_network).each do |project|
        s = ProjectServices::MigrateNetworkService.new(project, event)
        s.reload_lb = false
        if s.perform
          status << "Migrating project #{project.name} (#{project.id})"
        else
          errors << {
            project: project.id,
            errors: s.errors
          }
        end
      end

      event.event_details.create!(
        data: status.join("\n"),
        event_code: "66f4aeff7c356ea6"
      ) unless status.empty?

      # Reload the LB regardless of status
      LoadBalancerServices::DeployConfigService.new(region).perform

      if errors.empty?
        event.done!
        return
      end
      event.event_details.create!(
        data: errors.to_yaml,
        event_code: "06b70fbafae8f889"
      )
      event.fail! "General Error"
    rescue ActiveRecord::RecordNotFound
      nil
    rescue => e
      ExceptionAlertService.new(e, '3a0d4599b944bdf7').perform
      if defined?(event) && event
        event.event_details.create!(
          data: "Fatal Error: #{e.message}",
          event_code: "3a0d4599b944bdf7"
        )
        event.fail! "Fatal Error"
      end
    end
  end
end
