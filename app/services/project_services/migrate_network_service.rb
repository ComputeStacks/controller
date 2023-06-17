module ProjectServices

  ##
  # Migrate from Calico to Private Networks
  class MigrateNetworkService


    attr_reader :project,
                :event

    attr_accessor :errors,
                  :reload_lb

    # @param [Deployment] p
    # @param [EventLog] event
    def initialize(p, event)
      @project = p
      @event = event
      self.reload_lb = true
      self.errors = []
    end

    def perform

      # Generate private network
      unless NetworkServices::GenerateProjectNetworkService.new(@event, @project.region, @project).perform
        errors << "Failed to generate private network"
        return false
      end

      # Delete existing calico policies
      NetworkWorkers::TrashPolicyWorker.perform_async @project.region.id, @project.token
      (@project.services + @project.sftp_containers).each do |service|
        NetworkWorkers::TrashPolicyWorker.perform_async @project.region.id, service.name
      end

      nat_rules = []

      # Disable all NAT rules (but maintain NAT PORT so we don't lose that)
      (@project.services + @project.sftp_containers).each do |service|
        service.ingress_rules.lb.nat.each do |r|
          nat_rules << r
          # Skip callbacks
          r.update_column :external_access, false
        end
      end

      # Reload iptables to clear out old NAT rules
      unless nat_rules.empty?
        @project.region.nodes.each do |node|
          node.update_iptable_config!
        end
      end

      # Assign containers new IPs
      (@project.sftp_containers + @project.deployed_containers).each do |container|
        existing_ip = container.ip_address
        unless existing_ip.nil?
          unless existing_ip.destroy
            errors << "Error removing container IP Address! #{container.class.to_s}-#{container.id} -- #{existing_ip.errors.full_messages.join(' ')}"
            next
          end
        end
        container.reload
        unless container.set_ip_address!
          errors << "Fatal error provisioning IP for #{container.class.to_s}-#{container.id}"
          next
        end
        container.reload
        if container.ip_address.nil?
          errors << "Fatal error generating IP. #{container.class.to_s}-#{container.id}"
        end
      end

      return false unless errors.empty?

      # Bring back NAT rules
      nat_rules.each do |r|
        # Again, we want to skip any callbacks
        r.update_column :external_access, true
      end
      unless nat_rules.empty?
        @project.region.nodes.each do |node|
          node.update_iptable_config!
        end
      end

      # Rebuild containers -- will keep previous state
      (@project.sftp_containers + @project.deployed_containers).each do |container|
        ContainerWorkers::RebuildWorker.perform_async container.to_global_id.to_s, @event.to_global_id.to_s, true
      end

      return true unless reload_lb
      # Update LoadBalancer
      LoadBalancerServices::DeployConfigService.new(@project.region).perform
    end

    private

    def valid?
      if @project.nodes.count == 1
        if @project.region.has_clustered_networking?
          errors << "Region is not configured for private networking"
        end

        if @project.private_network
          errors << "Project already has a private network"
        end

        unless @project.sftp_containers.count == 1
          errors << "Project should have 1 sftp container"
        end

      else
        errors << "project includes containers on multiple nodes"
      end

      errors.empty?
    end

  end

end
