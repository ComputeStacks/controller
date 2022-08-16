module RegionServices
  class RegionMigratorService

    attr_accessor :region,
                  :new_region,
                  :event,
                  :errors

    # @param [Region] region
    # @param [Region] new_region
    def initialize(region, new_region)
      self.region = region
      self.new_region = new_region
      self.event = nil
      self.errors = []

      @skipped_services = [] # If there is an error, record here. We won't migrate anything else
      @skipped_volumes = [] # If there is an issue updating a volume, dont migrate it's data.
    end

    # @return [Boolean]
    def perform
      # Sanity Checks
      errors << "This region appears to have no containers" if region.containers.empty?
      errors << "Missing event" if event.nil?
      errors << "No online nodes found" if new_region.nodes.online.empty?
      return fail_process! unless errors.empty?

      # Setup Migration
      event.start!

      return fail_process! unless precheck
      return fail_process! unless infra_online?

      # Preflight
      region.nodes.each do |n|
        n.toggle_maintenance! unless n.maintenance
      end
      return fail_process! unless halt_containers

      ##
      # Perform Migration
      # No longer will fail if some resource has an issue. Point of no return!
      migrate_containers
      migrate_volumes
      boot
      cleanup

      # Ensure we capture any other errors
      event.event_details.create!(
        data: errors.join("\n"),
        event_code: "1c02551d43fa33e0"
      ) unless errors.empty?
      # Complete event
      event.done!
    rescue => e
      if event
        event.event_details.create!(
          data: errors.join("\n"),
          event_code: "f524a910890e5f10"
        ) unless errors.empty?
        event.event_details.create!(
          data: e.message,
          event_code: "f524a910890e5f10"
        )
        event.fail! "Fatal Error"
      end
      false
    end

    private

    ##
    # Before starting migration

    # @return [Boolean]
    def precheck
      # Ensure network range matches
      region.containers.each do |c|
        unless new_region.networks.where(cidr: c.network.cidr).exists?
          net_err_msg = "Missing network #{c.network.cidr} on target region"
          errors << net_err_msg unless errors.include? net_err_msg # no need to duplicate!
        end
      end
      # Users have access to new region
      region.container_services.each do |s|
        unless s.user.user_group.regions.include? new_region
          errors << "User #{s.user.email} does not have access to #{new_region.name}"
        end
      end
      # Ensure enough CPU Cores exist (container wont start without enough cpu cores)
      max_cores = region.containers.order(cpu: :desc).first.cpu
      max_avail_cores = 0
      region.nodes.each do |n|
        max_node = n.max_cpu_cores
        if max_node && max_node[:cpu] > max_avail_cores
          max_avail_cores = max_node[:cpu]
        end
      end
      if max_avail_cores < max_cores
        errors << "We require a minimum of #{max_cores} to migrate this region."
      end
      errors.empty?
    end

    # Check docker, ssh, and consul connectivity with new nodes
    # @return [Boolean]
    def infra_online?
      # Docker
      docker_client_opts = Docker.connection.options
      docker_client_opts[:connect_timeout] = 3
      docker_client_opts[:read_timeout] = 3
      docker_client_opts[:write_timeout] = 3
      new_region.nodes.each do |n|
        begin
          n.host_client.client.exec!("date")
        rescue
          errors << "Unable to connect via ssh: #{n.label}"
        end
        begin
          Docker.ping Docker::Connection.new("tcp://#{n.primary_ip}:2376", docker_client_opts)
        rescue
          errors << "Unable to connect to docker api: #{n.label}"
        end
      end

      # Consul
      dc = new_region.name.strip.downcase
      n = new_region.nodes.online.first.primary_ip
      begin
        Diplomat::Node.get_all({
                                 http_addr: Diplomat.configuration.options.empty? ? "http://#{n}:8500" : "https://#{n}:8501",
                                 dc: dc.blank? ? nil : dc,
                                 token: new_region.consul_token
                               })
      rescue
        errors << "Unable to connect to consul: #{new_region.name}"
      end

      errors.empty?
    end

    def halt_containers
      ##
      # Stop all containers
      container_names = []
      (region.containers + region.sftp_containers).each do |c|
        container_names << c.name unless container_names.include? c.name
        ContainerWorkers::StopWorker.perform_async c.to_global_id.to_s, event.to_global_id.to_s
      end
      stop_detail = event.event_details.create!(
        data: "Attempting to stop containers: \n\n #{container_names.join("\n")}",
        event_code: "b3af0b7353e0df8e"
      )
      loop_timeout = (container_names.count * 10.seconds + 3.minutes).from_now
      successful_stop = false
      while loop_timeout > Time.now do
        stopped_containers = []
        running_containers = []
        (region.containers + region.sftp_containers).each do |c|
          # updated every 10 seconds.
          if c.is_a?(Deployment::Sftp)
            stopped_containers << c.name
            next
          end
          if c.metric_last_seen.nil?
            stopped_containers << c.name
            next
          end
          (c.metric_last_seen < 15.seconds.ago) ? (stopped_containers << c.name) : (running_containers << c.name)
        end

        if running_containers.empty?
          successful_stop = true
          stop_detail.update data: "Successfully stopped containers: \n\n#{stopped_containers.join("\n")}"
          break
        end

        unless stopped_containers.empty?
          stop_detail.update data: "Successfully stopped containers: \n\n#{stopped_containers.join("\n")}\n\n---\n\nAttempting to stop containers: \n\n#{running_containers.join("\n")}"
        end

        sleep 2
      end
      unless successful_stop
        errors << "Failed to stop all containers. Please manually stop containers and try again"
      end
      successful_stop
    end

    ##
    # Perform Resource Migration

    def migrate_containers
      # Assign containers to new region (pick new nodes)
      region.container_services.each do |service|
        unless service.update region: new_region
          errors << "Failed to update service #{service.name}: #{service.errors.full_messages.join(". ")}"
          @skipped_services << service
          next
        end

        # Clustered Storage: Each container can be placed on any node
        # Also used if no volumes are present for this service
        if new_region.has_clustered_storage? || service.volumes.empty?
          service.containers.each do |c|
            next if c.node.region == new_region
            n = new_region.find_node c.package_for_node
            if n.nil?
              errors << "Unable to find node for service #{service.name}, container #{c.name}."
              @skipped_services << service
              next
            end
            unless c.update node: n
              errors << "Error setting new node for container #{c.name} (node: #{n.label})"
              @skipped_services << service
            end
          end
        else
          # Local storage: Each service uses a single node for all containers
          new_node = new_region.find_node service.package_for_node
          if new_node.nil?
            errors << "Unable to find node for service #{service.name}"
            @skipped_services << service
            next
          end
          service.containers.each do |c|
            unless c.update node: new_node
              errors << "Error setting new node for container #{c.name} (node: #{new_node.label})"
              @skipped_services << service
            end
          end

        end
      end
      event.event_details.create!(
        data: "Skipped the following services due to an error setting the new node: \n\n#{@skipped_services.join("\n")}",
        event_code: "e520c7b300b2326d"
      )

      # Assign containers to new network
      new_ips = []
      new_region.containers.each do |c|
        new_net = new_region.networks.find_by(cidr: c.network.cidr)
        if new_net.nil? # shouldn't happen, since we check early on if the net exists
          errors << "Failed to find network for container #{c.name}"
          next
        end
        in_use = new_net.addresses.pluck(:cidr)
        # if the IP is in use, allocate a new one and record the change
        if in_use.include? c.ip_addr
          new_ip = new_net.next_ip
          new_ips << "[#{c.name}] #{c.ip_addr} -> #{new_ip}"
          c.ip_address.update network: new_net, cidr: "#{new_ip}/32"
        else
          c.ip_address.update network: new_net
        end
      end
      event.event_details.create!(
        data: "Unable to retain all previous IPs due to conflicts: \n\n#{new_ips.join("\n")}",
        event_code: "5dededa4b3e03588"
      ) unless new_ips.empty?
    end

    def migrate_volumes
      # Update volume to new region
      new_region.container_services.each do |s|
        next if @skipped_services.include? s
        volume_driver = if s.container_image.force_local_volume
                          'local'
                        else
                          new_region.volume_backend
                        end
        s.volumes.each do |vol|
          unless vol.update volume_backend: volume_driver, region: new_region, nodes: (volume_driver == 'nfs' ? new_region.nodes : s.nodes)
            errors << "Error updating volume #{vol.name} for service #{s.name}: #{vol.errors.full_messages.join(" ")}"
            @skipped_volumes << vol
            next
          end

          # Create the volume on the new region
          unless VolumeServices::ProvisionVolumeService.new(vol, event).perform
            errors << "Error creating volume #{vol.name} for service #{s.name}"
            @skipped_volumes << vol
          end

        end
      end
    end

    ##
    # TODO: Migrate Volume Data
    # def transfer_volumes

    # Get raw path of original volume
    # Get raw path of new volume
    # SSH into new node (or nfs server)
    # rsync original node from full path to new location
    #
    # #!/usr/bin/env bash
    #
    # set -e
    #
    # for d in /var/lib/docker/volumes/*
    # do
    #   ( VOL_ID=$(echo "$d" | sed -e 's/\/.*\///g'); if [ -d "$d/_data" ];then rsync -aP $d/_data/ root@185.63.155.8:/var/nfsshare/volumes/$VOL_ID/; fi  )
    # done

    # end

    ##
    # Start Services
    # @return [Boolean]
    def boot
      projects = []
      new_region.container_services.each do |s|
        next if @skipped_services.include? s
        NetworkWorkers::ServicePolicyWorker.perform_async s.id
        sleep 1
        unless projects.include? s.deployment
          NetworkWorkers::ProjectPolicyWorker.perform_async s.deployment.to_global_id.to_s
          projects << s.deployment
        end
        sleep 1
      end
      container_names = []
      new_region.containers.each do |c|
        next if @skipped_services.include? c.service
        container_names << c.name unless container_names.include? c.name
        ContainerWorkers::RebuildWorker.perform_async c.to_global_id.to_s, event.to_global_id.to_s
        sleep 2
      end
      event.event_details.create!(
        data: "Attempting to build containers: \n\n #{container_names.join("\n")}",
        event_code: "b3af0b7353e0df8e"
      )
      # Trigger SFTP Generation
      projects.each do |p|
        ProjectWorkers::SftpInitWorker.perform_in(5.minutes, p.to_global_id.to_s, event.to_global_id.to_s)
      end
      project_names = projects.map { |i| i.name }
      event.event_details.create!(
        data: "Triggering SFTP provisioner for projects (Will start in 5 minutes): \n\n#{project_names.join("\n")}",
        event_code: "2a1f0b15ee2e0946"
      )
      true
    end

    def cleanup
      # Remove all services (except @skipped_services) from old nodes
      # Leave volume data!!
    end

    # @return [Boolean]
    def fail_process!
      if event
        event.event_details.create!(
          data: errors.join("\n"),
          event_code: "53a5ab54deeb1ecd"
        )
        event.fail! "Migration Error"
      end
      false
    end

  end
end
