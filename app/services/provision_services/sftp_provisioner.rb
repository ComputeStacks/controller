module ProvisionServices
  # Provision SFTP Containers for a single project
  #
  # This can be run multiple times and will determine the correct number, and location, of sftp containers.
  #
  # Rules are:
  # * Keep at least 1 SFTP container per-project
  # * When deleting un-used SFTP containers, try to re-use the existing public port
  #
  # @!attribute project
  #   @return [Deployment]
  # @!attribute errors
  #   @return [Array]
  class SftpProvisioner

    attr_accessor :project,
                  :event,
                  :errors

    # @param [Deployment] project
    def initialize(project, event)
      self.project = project
      self.event = event
      self.errors = []
    end

    # @return [Boolean]
    def perform
      if project.nodes.available.empty?
        errors << "This project has no available nodes!"
        return false
      end
      nodes = [] # Nodes that require an sftp container

      # 1. Determine which services require a local sftp container
      if project.has_clustered_storage?
        # Clustered storage: Choose a single node based on our container placement algorithm.
        regions = project.volumes.select(:region_id).distinct.map { |i| i.region }
        regions.each do |r|
          # Reuse existing sftp container when possible
          existing_sftp = project.sftp_containers.where(nodes: { region: r }).joins(:node)
          existing_sftp.each do |i|
            nodes << i.node unless nodes.include? i.node
          end
          if existing_sftp.empty?
            new_node = r.find_node BillingPackage.new(cpu: 1, memory: 512)
            nodes << new_node unless nodes.include? new_node
          end
        end
      else
        # Local storage: Pin container to same host as volume
        project.volumes.where(enable_sftp: true).each do |vol|
          n = vol.nodes.online.empty? ? vol.nodes.first : vol.nodes.online.first
          next if nodes.include?(n)
          nodes << n
        end
      end

      # 2. If nodes are empty, add one of the existing in-use nodes so we have at least 1 SFTP container
      if nodes.empty? && project.sftp_containers.active.empty? # Don't add if we already have one.
        nodes << project.nodes.available.first
      elsif nodes.empty? && project.sftp_containers.active.count == 1
        # Don't require any nodes to have one,
        # and we already have an existing SFTP container in this project.
        return true
      elsif nodes.empty?
        # We don't require any new sftp containers,
        # but we have more than 1, so we need to clean it up.

        # Add one of the existing in-use nodes as the node
        nodes << project.sftp_containers.active.first.node
      end

      # Shouldn't happen! But catch it, if it does.
      if nodes.empty?
        errors << "Unknown error occurred."
        errors << "We ended up with no nodes asking for an SFTP container!"
        return false
      end

      # 3. If SSH is disabled, empty out nodes so we delete existing ones.
      nodes = [] if project.skip_ssh

      # 4. Cleanup existing SFTP containers
      project.sftp_containers.active.each do |i|
        next if nodes.include? i.node # We need this one!
        ContainerServices::TrashContainer.new(i, event).perform
      end

      # 5. Provision any new sftp containers
      nodes.each do |node|
        # Skip if we already have an SFTP container on this node
        next if project.sftp_containers.active.where(node: node).exists?

        load_balancer = LoadBalancer.find_by_node node
        if load_balancer.nil?
          errors << "Missing load balancer for node #{node.label} (#{node.id})"
          next
        end

        sftp = project.sftp_containers.new(
          node: node,
          name: NamesGenerator.name(project.id),
          load_balancer: load_balancer,
          pw_auth: project.user.c_sftp_pass
        )
        unless sftp.save
          errors << sftp.errors.full_messages.join(' ')
          next
        end
      end
      errors.empty?
    end

  end
end
