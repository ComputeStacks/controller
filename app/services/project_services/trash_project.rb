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
      ActiveRecord::Base.uncached do
        clean_metadata_tenant!
        if project.private_network
          # Immediately remove our link to it
          project.private_network.update deployment_id: nil
        else
          clean_network_policy!
        end
        trash_sftp_containers! # failure can be ignored
        return false unless trash_services!
        project.reload
        return true if project.destroy
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

    def clean_metadata_tenant!
      project.regions.all.each do |i|
        Agent::Client.new(project, region: i).deprovision_tenant!
      rescue Agent::Client::NotReady
        next
      end
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
