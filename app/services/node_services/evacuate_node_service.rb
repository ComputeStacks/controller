module NodeServices
  ##
  # Process an evacuation request for a node
  #
  # This can happen automatically when a node is offline,
  # or when an admin specifically requests it.
  #
  # @!attribute node
  #   @return [Node]
  # @!attribute event
  #   @return [EventLog]
  class EvacuateNodeService

    attr_accessor :node,
                  :event

    # @param [Node] node
    # @param [EventLog] event
    def initialize(node, event)
      self.node = node
      self.event = event
      @touched_deployments = []
    end

    # @return [Boolean]
    def perform
      event.start!
      return false unless valid?

      # Quickly flag containers as migrating
      node.containers.update_all status: 'migrating'

      trash_sftp!

      # TODO: Prioritize databases over webapps
      node.containers.each do |container|
        @touched_deployments << container.deployment unless @touched_deployments.include?(container.deployment)
        migrate_container! container
      end

      build_sftp!

      # Update volumes
      node.volumes.each do |vol|
        vol.update_consul!
      end

      # Done
      node.toggle_evacuation!
      event.done! if event.active?
      true
    end

    private

    # @return [Boolean]
    def valid?
      if node.under_evacuation? && (Time.now - node.job_performed) < 15.minutes
        event.event_details.create!(
          data: "Already under evacuation, skipping..",
          event_code: 'e318f7d65b7c1365'
        )
        event.cancel! 'Already migrating'
        return false
      elsif node.under_evacuation? && (Time.now - node.job_performed) > 15.minutes
        # re-update the clock
        node.update_attribute :job_performed, Time.now
      elsif !node.under_evacuation?
        node.toggle_evacuation!
      end
      true
    end

    # @param [Deployment::Container] container
    def migrate_container!(container)
      container_event = EventLog.create!(
        locale: 'container.migrating',
        locale_keys: { 'container' => container.name },
        event_code: '4c7a96039fac57d9',
        status: 'pending',
        audit: event.audit
      )
      container_event.containers << container
      container_event.deployments << container.deployment
      container_event.container_services << container.service
      migrator = ContainerMigratorService.new(container, container_event)
      if migrator.perform
        event.event_details.create!(
          data: "Successfully migrated #{container.name} from #{node.label} to #{migrator.new_node.label}",
          event_code: '6d2f56c959ec733e'
        )
      else
        event.event_details.create!(
          data: %Q(failed to migrate container #{container.name}\n\n#{container_event.event_details.pluck(:data).join("\n")}),
          event_code: 'c7b8c6d6330399b9'
        )
        false
      end
    end

    def trash_sftp!
      node.sftp_containers.each do |i|
        i.update_column :to_trash, true
        i.delete_now!(event.audit) unless node.disconnected
        i.destroy
      end
    end

    def build_sftp!
      @touched_deployments.each do |d|
        ProvisionServices::SftpProvisioner.new(d, event).perform
        DeployServices::DeployProjectService.new(d, event).perform
      end
    end

  end
end
