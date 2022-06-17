module VolumeServices
  ##
  # Sync volumes
  #
  # This will only look for locally-created volumes, like those
  # automatically created when a user forgets to define a `VOLUME` in
  # ComputeStacks.
  #
  # This will do two things:
  # * Disables backups on that volume
  # * Pins the container to this node (when using clustered storage)
  #
  # @!attribute event
  #   @return [EventLog]
  class SyncVolumeService

    attr_accessor :event,
                  :skipped_volumes

    # @param [EventLog] event
    def initialize(event)
      self.event = event
      self.skipped_volumes = {}
    end

    # @return [Boolean]
    def perform
      Node.online.each do |node|
        begin
          # Returns an array of Docker::Volume
          available_volumes = DockerVolumeLocal::Node.new(node).list_all_volumes
        rescue => e # Allow us to gracefully fail for an offline node
          ExceptionAlertService.new(e, '9c158106939a83f9').perform
          next
        end

        # Need to list out all containers and their attached volumes in
        # order to figure out where these volumes are mounted.

        available_volumes.each do |vol|
          if vol.info.dig("Labels", "com.computestacks.role")
            next if %w(backup system).include? vol.info["Labels"]["com.computestacks.role"]
            next if vol.info['Name'] == 'consul-data'
          end

          ##
          # For existing volumes, we just want to note that it exists on this node.
          existing_volume = Volume.find_by(name: vol.info['Name'])
          if existing_volume
            unless existing_volume.nodes.include?(node)
              existing_volume.nodes << node
              event.event_details.create!(
                data: "Found volume #{vol.info['Name']} on a new node: #{node.label}; updating...",
                event_code: '8e101399a65eabb8'
              )
            end
            next
          end

          import_volume(vol, node)

        end
      end
      unless skipped_volumes.empty?
        event.event_details.create!(
          data: "Found the following volumes, but skipped due to missing local service:\n\n#{skipped_volumes.to_yaml}",
          event_code: 'ad0490ed8c707384'
        )
      end
      return false if event.failed?
      event.done!
      true
    end

    private

    # @param [Docker::Volume] vol
    # @param [Node] node
    def import_volume(vol, node)
      ##
      # Identify existing services
      existing_container_service = nil
      service_mount_path = nil

      volume_inspect = Volume.inspect_volume_by_name vol.info['Name']
      volume_inspect.each do |i|
        next if i[:container_name].blank?
        c = Deployment::Container.find_by(name: i[:container_name])
        next if c.nil?
        existing_container_service = c.service
        service_mount_path = i[:mount_path]
      end

      if existing_container_service.nil? # Skip it!
        (skipped_volumes[node.label] ||= []) << vol.info['Name']
        return
      end

      new_volume = existing_container_service.volumes.new(
        label: vol.info['Name'],
        name: vol.info['Name'],
        deployment: existing_container_service.deployment,
        user: existing_container_service.deployment.user,
        borg_enabled: false,
        enable_sftp: false,
        region: existing_container_service.region,
        volume_backend: 'local' # TODO: Read the drive from the docker api.
      )
      new_volume.nodes << node
      unless new_volume.save
        new_volume.volume_maps.create!(
          mount_path: service_mount_path,
          container_service: existing_container_service
        )
        event.event_details.create!(
          data: "Fatal error importing volume #{vol.info['Name']}.\n\n#{new_volume.errors.full_messages.join(' ')}",
          event_code: '23d980fd2ed94884'
        )
        event.fail! 'Error creating volume'
        return
      end
      event.event_details.create!(
        data: "Imported volume: #{new_volume.name} for service #{existing_container_service.label} (#{existing_container_service.id}).\n\nMounted at: #{service_mount_path}",
        event_code: 'b996ebd83c79b1cd'
      )
      new_volume.update_consul!
    end

  end
end
