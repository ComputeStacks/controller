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
  # @!attribute warnings
  #   @return [Array]
  class SftpProvisioner
    ##
    # "We could not place an SFTP container here, and skipped it."
    #
    # The payload under this code is OPERATOR-facing. Region#context describes a placement
    # failure in the vocabulary of the placement algorithm -- `{metric_cpu_cores: 0,
    # requested_cpu: 1.0}` is what an unreachable metrics server looks like, and telling a
    # customer their node has no CPUs would be worse than saying nothing.
    PLACEMENT_SKIPPED_EVENT_CODE = "28c7641797aa6c1d"

    attr_accessor :project,
      :event,
      :errors,
      :warnings

    # @param [Deployment] project
    def initialize(project, event)
      self.project = project
      self.event = event
      self.errors = []
      self.warnings = []
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
          existing_sftp = project.sftp_containers.where(nodes: {region: r}).joins(:node)
          existing_sftp.each do |i|
            nodes << i.node unless nodes.include? i.node
          end
          if existing_sftp.empty?
            # The size the node will actually enforce for this container. Asking for
            # less than that could pick a node with no room for it.
            new_node = r.find_node BillingPackage.new(
              cpu: Deployment::Sftp::ALLOCATED_CPU,
              memory: Deployment::Sftp::ALLOCATED_MEMORY
            )
            # A zone we cannot place into is a WARNING, never an error -- see
            # #record_placement_warning. Pushing the nil through instead was a data-loss
            # bug: a `nodes` of [nil] is not `empty?`, so the step-2 ladder below never
            # ran, and step 4 then trashed the project's only surviving SFTP container
            # because [nil] does not include its node. That is exactly what a volume
            # migration A -> B produces, since `regions` derives from the volumes and so
            # never mentions the region the existing container is actually in.
            if new_node.nil?
              record_placement_warning "Could not place an SFTP container in #{r.name}.",
                r.context
              next
            end
            nodes << new_node unless nodes.include? new_node
          end
        end
      else
        # Local storage: Pin container to same host as volume
        project.volumes.where(enable_sftp: true).each do |vol|
          n = vol.nodes.online.empty? ? vol.nodes.first : vol.nodes.online.first
          # A volume with no node associations at all. Deliberately NOT routed through
          # Volume#find_node: that has a different fallback chain and would change which
          # node gets picked for every volume, not just this one.
          if n.nil?
            record_placement_warning "Could not place an SFTP container for volume #{vol.label}.",
              {volume: vol.id, label: vol.label, region: vol.region&.name, nodes: 0}
            next
          end
          next if nodes.include?(n)
          nodes << n
        end
      end

      # Belt and braces after the two guards above. Statement only: Array#compact!
      # returns nil when it removes nothing, so assigning it back would be fatal.
      nodes.compact!

      # 2. If nodes are empty, add one of the existing in-use nodes so we have at least 1 SFTP container
      if nodes.empty? && project.sftp_containers.active.empty? # Don't add if we already have one.
        fallback_node = project.nodes.available.first
        if fallback_node.nil?
          # Genuinely nothing to place anything on -- an error this time, not a warning.
          # Reachable when a node is deactivated between the check at the top of this
          # method and here.
          errors << "This project has no available nodes!"
          return false
        end
        nodes << fallback_node
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
          errors << "Missing load balancer for node #{node&.label} (#{node&.id})"
          next
        end

        sftp = project.sftp_containers.new(
          node: node,
          name: NamesGenerator.name(project.id),
          load_balancer: load_balancer,
          pw_auth: project.user.c_sftp_pass
        )
        unless sftp.save
          errors << sftp.errors.full_messages.join(" ")
          next
        end
      end
      errors.empty?
    end

    private

    ##
    # Record a zone (or volume) we could not place into, without failing the run.
    #
    # #perform returns `errors.empty?`, so anything pushed onto `errors` fails the whole
    # provisioning run -- and on the order path ProcessOrderService#finalize! turns that
    # false into its own error, which makes it call fail_process!, which detaches the
    # private network of a project whose containers are already built and running. A
    # placement hiccup must never do that.
    #
    # The warning also goes onto the event log rather than living only in `warnings`,
    # because the step-2 ladder can `return true` before the caller ever looks at this
    # object.
    #
    # @param message [String] customer-safe
    # @param context [Hash, nil] operator-only detail
    # @return [void]
    def record_placement_warning(message, context = nil)
      warnings << message

      # TWO channels, deliberately. app/views/event_logs/_show.html.erb is the CUSTOMER's
      # event log and renders event_details raw, so only the plain sentence goes there --
      # they do need to know an SFTP container was not created. The diagnostic goes to a
      # SystemEvent, which is admin-only: Region#context speaks the placement algorithm's
      # vocabulary, and `{metric_cpu_cores: 0, requested_cpu: 1.0}` is what an unreachable
      # metrics server looks like. Showing a customer that their node has no CPUs would be
      # worse than saying nothing.
      # SEPARATE rescues, deliberately. The operator's record is the one that must survive
      # -- the step-2 ladder can `return true` before anyone reads `warnings` -- and a
      # shared rescue meant a purged or invalid EventLog took the SystemEvent down with it,
      # leaving a skipped placement with no operator-visible trace at all.
      begin
        SystemEvent.create!(
          message: "SFTP placement skipped",
          log_level: "warn",
          data: {
            "project" => {"id" => project&.id, "name" => project&.name},
            "reason" => message,
            "context" => context
          },
          event_code: PLACEMENT_SKIPPED_EVENT_CODE
        )
      rescue => e
        Rails.logger.warn "SftpProvisioner could not record a placement SystemEvent: #{e.class}"
      end

      begin
        event&.event_details&.create!(data: message, event_code: PLACEMENT_SKIPPED_EVENT_CODE)
      rescue => e
        # Never let bookkeeping be the thing that fails a provisioning run.
        Rails.logger.warn "SftpProvisioner could not record a placement warning: #{e.class}"
      end
    end
  end
end
