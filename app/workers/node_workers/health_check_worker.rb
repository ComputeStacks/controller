module NodeWorkers
  class HealthCheckWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(node_id = nil)

      if node_id.nil?
        Node.online.each do |i|
          NodeWorkers::HealthCheckWorker.perform_async i.global_id
        end
        return
      end
      # @type [Node] node
      node = GlobalID::Locator.locate node_id
      return if node.nil? || !node.online?
      return if node.under_evacuation? || node.performing_checkup?


      expected_containers = node.containers.where.not(status: 'migrating').pluck(:name)
      expected_containers += node.sftp_containers.where(to_trash: false).pluck(:name)
      have_containers = []
      containers_on_node = node.list_all_containers
      return if containers_on_node.empty? # Skip if this is empty. Trying to catch odd empty results.

      containers_on_node.each do |i|
        next if ignore_container?(i)
        container_name = i.info['Names'].first.gsub("/", '').strip

        ## deprecated
        next if container_name == 'calico-node' || i.info['Image'] == "calico/node"
        next if SYSTEM_CONTAINER_NAMES.include? container_name
        ## end

        have_containers << container_name
      end

      # Expected, but not present on node.
      (expected_containers - have_containers).each do |i|
        c = Deployment::Container.find_by(name: i)
        c = Deployment::Sftp.find_by(name: i, to_trash: false) if c.nil?
        next if c.nil?
        next if %w(building migrating).include? c.status
        next if c.created_at > 3.minutes.ago
        next unless c.active? # Ignore containers that have been stopped
        failed_attempts = c.event_logs.where( Arel.sql(%Q(created_at >= '#{1.hour.ago.iso8601}')) ).starting.failed.count
        return halt_recovery! c if failed_attempts > 3
        ContainerWorkers::RecoverContainerWorker.perform_async c.global_id
      end

      ##
      # Have, but not expected, containers
      (have_containers - expected_containers).each do |i|
        obj = Deployment::Container.find_by(name: i)
        obj = Deployment::Sftp.find_by(name: i) if obj.nil?
        obj = LoadBalancer.find_by(name: i) if obj.nil?

        if obj.nil?
          trash_container! i, node
          next
        else
          next if obj.respond_to?(:status) && %w(building migrating).include?(obj.status)
          next if obj.node == node
          trash_container!(i, node)
        end
      end

      clist = {}
      # Format container list
      containers_on_node.each do |i|
        clist[i.info['Names'].first.gsub("/", '')] = {
          status: i.info['State'] == 'exited' ? 'stopped' : i.info['State'],
          network: i.info.dig('NetworkSettings', 'Networks')&.keys&.first
        }
      end

      (node.containers + node.sftp_containers).each do |i|
        next if clist[i.name].nil?
        cstatus = clist[i.name][:status]
        has_network = clist[i.name][:network]

        next if i.is_a?(Deployment::Container) && i.service.nil?

        next if i.deployment.nil?
        next if i.created_at > 4.minutes.ago # ignore new containers.

        # Billing!
        i.update_subscription_by_status!(cstatus.downcase) if i.is_a?(Deployment::Container)

        # Clean stopped containers (if option enabled)
        if %w(stopped exited).include?(cstatus.downcase) && i.is_a?(Deployment::Container)
          if i.can_delete_stopped? && !i.active?
            # Remove stopped containers (if allowed)
            begin
              i.docker_client&.delete
            rescue => e
              ExceptionAlertService.new(e, 'ae5da137f17be45a').perform
            end
          end
        end

        next unless i.requires_intervention? cstatus.downcase
        return halt_recovery!(i) if i.halt_auto_recovery?

        case cstatus.downcase
        when 'created', 'stopped', 'exited'
          if i.active?
            next if i.is_a?(Deployment::Container) && i.restore_in_progress?
            if has_network
              ContainerWorkers::RecoverContainerWorker.perform_async i.global_id
            else
              audit = Audit.create_from_object!(i, 'updated', '127.0.0.1')
              PowerCycleContainerService.new(i, 'rebuild', audit).perform
            end
          end
        when 'running'
          unless i.active?
            audit = Audit.create_from_object!(i, 'updated', '127.0.0.1')
            PowerCycleContainerService.new(i, 'stop', audit).perform
          end
        else
          next
        end
      end

    end

    private

    ##
    # Trash a container
    #
    # Will skip if container has the label `CS_IGNORE`
    #
    # @param [String] name
    # @param [Node] node
    # @return [Boolean]
    def trash_container!(name, node)
      return true if name =~ /backup/
      client = Docker::Container.get(name, {}, node.fast_client)
      return true unless client.is_a?(Docker::Container)
      if client.info.dig('Config', 'Labels', 'CS_IGNORE')
        title = "Unknown container #{name} found on #{node.label}"
        # only create 2 per day
        unless SystemEvent.where( Arel.sql( %Q(event_code = '86ce8953d9fcd59d' AND message = '#{title}' AND created_at >= '#{12.hours.ago.iso8601}') ) ).exists?
          SystemEvent.create!(
            message: title,
            log_level: 'notice',
            data: {
              message: "Unknown container #{name} has been found on node #{node.label}, however we are not removing it because the label CS_IGNORE has been found. Please manually clean this container up"
            },
            event_code: '86ce8953d9fcd59d'
          )
        end
        return true
      end
      client.stop
      sleep(2)
      client.delete
      true
    rescue Docker::Error::ConflictError # {"message":"removal of container xxx is already in progress"}
      true
    rescue Docker::Error::NotFoundError # already gone!
      true
    rescue => e
      ExceptionAlertService.new(e, '5a6116453c836356').perform
      true
    end

    def halt_recovery!(container)
      container.set_inactive!
      event = container.event_logs.create!(
        locale: 'container.errors.stay_online',
        locale_keys: {
          label: container.name,
          container: container.name
        },
        event_code: '459363d1cbcce0c3',
        notice: true,
        status: 'completed'
      )
      event.deployments << container.deployment
      event.container_services << container.service if container.is_a?(Deployment::Container)
      SystemEvent.create!(
        message: "Failed to recover container: #{container.name}",
        log_level: 'warn',
        data: {
          message: "Auto-recovery has failed too many times.",
          obj_id: container.global_id.to_s,
        },
        event_code: '459363d1cbcce0c3'
      )
      ProcessAppEventWorker.perform_async 'ContainerBootFailed', container.user&.global_id, container.global_id
    end

    # @param [Docker::Container] container
    # @return [Boolean]
    def ignore_container?(container)
      return false if container.info['Labels'].empty?
      %w(backup system).include? container.info['Labels']['com.computestacks.role']
    end

  end
end

