class ProcessOrderService
  attr_accessor :order,
    :event,
    :region,
    :project,
    :container_service, # The created service
    :region,
    :result,
    :errors

  def initialize(order)
    self.order = order
    # SFTP containers are not tracked in `result`; this tells this order's apart (see
    # ensure_container_networks!).
    @started_at = Time.current
    self.event = order.current_event
    self.project = order.deployment.nil? ? nil : order.deployment
    self.region = if order.data[:region_id].blank?
      nil
    else
      Region.find_by id: order.data[:region_id]
    end
    self.errors = []

    ##
    # The private network this project ALREADY had when the order arrived, if any.
    #
    # An order against an existing project does not allocate a network --
    # NetworkServices::GenerateProjectNetworkService returns early with "Project network
    # already configured, skipping". So the network is not this order's to release, and
    # releasing it strips a running project of its network record: every later read of
    # `project.private_network` answers nil, and the ten-minute cleanup sweep starts
    # considering a live customer's network for deletion, held off only by its addresses.
    #
    # Seen in production on 2026-09-04: a second order against a project provisioned the day
    # before failed, and six seconds later that project's network row was detached while its
    # three containers and its SFTP container carried on running.
    #
    # nil when the project is new, or had no network yet -- in both of those cases this order
    # allocated whatever is there now and must release it on failure.
    @inherited_network_id = order.deployment&.private_network&.id

    ## Track what we've done.
    # result = {
    #   containers: [],
    #   subscriptions: [],
    #   load_balancers: [],
    #   volumes: []
    # }
    self.result = {
      containers: [],
      subscriptions: [],
      load_balancers: [],
      volumes: [],
      volume_map: [], # [ { template: csrn, volume: csrn } ]
      volume_clones: [] # [ { vol_id: int, source_vol_id: int, source_snap: string } ]
    }
  end

  def perform
    event.start!
    unless valid?
      fail_process! "Invalid order parameters"
      return false
    end
    order.processing!
    unless within_quota?
      fail_process! "Over quota"
      return false
    end
    if order.requires_project? && !init_project!
      fail_process! "Failed to find or create project"
      return false
    end

    unless region.has_clustered_networking?
      # Link private net to project
      unless NetworkServices::GenerateProjectNetworkService.new(event, region, project).perform
        fail_process! "Failed to build project network"
        return false
      end
    end

    # Dependencies first (the database before the site that needs it), and stop at the first
    # product that fails: anything provisioned after a failed dependency would only be left
    # behind half-built. A failed order is reported, never rolled back.
    to_provision = OrderServices::ProductDependencySorter.new(order.data[:raw_order]).perform
    loop_end = 3.minutes.from_now
    loop do
      break if to_provision.empty?
      break if loop_end <= Time.now
      # Walk a snapshot, so removing a finished product never skips its neighbor.
      to_provision.dup.each do |product|
        base_job = case product[:product_type]
        when "container"
          OrderServices::ContainerServiceOrderService
        end
        next if base_job.nil?

        job = base_job.new(order, event, project, product)

        # Keep pushing the result forward so each cycle can track what's been done so far.
        job.provision_state = result

        # Not a failure: its volumes aren't ready yet, so it is retried on the next pass.
        next unless job.ready_to_provision?

        job_status = job.perform
        job.errors.each do |err|
          errors << err
        end

        # Combine results hash so the next cycle will have it.
        result.merge!(job.result) do |k, a, b|
          a + b
        end

        # If it fails, but for some reason does not provide errors,
        # make sure we capture that and stop the order process from finalizing
        errors << "Failed to build product" if job.errors.empty? && !job_status

        # Remove this from the stack -- by identity, so an order for two identical products
        # still builds both.
        to_provision.delete_if { |p| p.equal?(product) }

        # Fail fast: start nothing after a failed product.
        break unless errors.empty?
      end
      break unless errors.empty?
      sleep 2
    end
    unless to_provision.empty? && errors.empty?
      fail_process! "Failed to provision all resources"
      return false
    end
    unless finalize!
      fail_process! "Error on order cleanup"
      return false
    end
    complete_process!
    true
  rescue => e
    # Kept for fail_process!'s failure reason; the ensure below fails the order.
    @fatal_error = e
    raise
  ensure
    # If this is triggered and the event is still running, then something bad happened.
    if event.running?
      fail_process! "Fatal Error"
    end
  end

  private

  def within_quota?
    requested_containers = 0
    order.data[:raw_order].each do |i|
      next unless i[:product_type] == "container"
      requested_containers += i[:qty].to_i
    end
    order.user.can_order_containers? requested_containers
  end

  def init_project!
    if order.deployment
      self.project = order.deployment
    else
      if order.data[:project][:skip_ssh]
        event.event_details.create!(
          data: "Skipping SSH creation due to skip_ssh flag",
          event_code: "b1f2ff50217bd39e"
        )
      end
      # First determine if we need an order
      d = order.build_deployment(
        user: order.user,
        name: order.data[:project][:name],
        skip_ssh: order.data[:project][:skip_ssh]
      )
      unless d.save
        errors << "Failed to create project"
        event.event_details.create!(
          data: "Failed to create project: #{d.errors.full_messages.join(" ")}",
          event_code: "30dba49646cfd9f4"
        )
        return false
      end
      self.project = d
      order.save # Ensure project is mapped to this order
    end
    event.deployments << project unless event.deployments.include?(project)
    true
  end

  # Finalize the service provisioning
  #
  # At this point, there is no rolling back. All of the services and subscriptions are generated, so we're not going to try and rollback.
  #
  # Instead, gracefully fail on those items that didn't make it, and allow the user/admin to inspect the current state and attempt to recover manually.
  def finalize!
    # Project does not have the private network, so we need to reload from the DB.
    project.reload

    # Mint the customer metadata Bearer (replaces the retired Consul ACL token)
    # and provision the project's tenant on the node agent. Must run here, before
    # the SFTP/ssh-keys managed writes below, because the agent rejects writes for
    # an unprovisioned tenant (B2).
    if project.consul_auth_key.blank? && !project.update(consul_auth_key: SecureRandom.urlsafe_base64(32))
      errors << "Failed to set project metadata auth key"
      return false
    end
    begin
      # A false return or NotReady is recorded as a pending `tenant` sync and replayed by
      # AgentWorkers::PendingSyncWorker.
      Agent::PendingSync.track(record_drop: true, region: region, project: project, kind: "tenant") do
        Agent::Client.new(project, region: region).provision_tenant!
      end
    rescue Agent::Client::NotReady => e
      # Non-fatal: the managed-blob writers self-heal provisioning on first write.
      # Record it on the event rather than in `errors` — by this point every
      # container is already built, and an errors entry would fail the order
      # (fail_process! releases the project's private network) over a condition
      # that resolves itself on the next managed write.
      event.event_details.create!(
        data: "Could not provision metadata tenant on the node agent: #{e.message}. " \
              "This will be retried automatically on the next metadata write.",
        event_code: "7239068cdeb3b779"
      )
    end

    # Ensure proper SFTP layout
    sftp_provisioner = ProvisionServices::SftpProvisioner.new(project, event)
    unless sftp_provisioner.perform
      errors << "Failed to create sftp resources" # Add this in case the provisioner did not return any errors (because of a bug or exception)
      sftp_provisioner.errors.each do |err|
        errors << err
      end
    end

    # Store current known publish ssh keys for sftp containers to pull.
    ProjectServices::MetadataSshKeys.new(project).perform

    # Unlike the tenant above, this one IS an order failure: a container with no private
    # network or IP gets no runtime config, and DeployProjectService would queue a build that
    # can only fail. Stop here, before any build is queued.
    return false unless ensure_container_networks!

    # Actually provision the resources on the compute resources
    resource_provisioner = DeployServices::DeployProjectService.new(project, event)
    resource_provisioner.volume_clones = result[:volume_clones]
    unless resource_provisioner.perform
      errors << "Failed to provision resources"
      resource_provisioner.errors.each do |er|
        errors << er
      end
    end

    # Volume data restores are scheduled, not awaited — the order completes as soon as the
    # containers are built. Say so, because the project is usable immediately but its volumes
    # fill in over the following minutes (or hours, for a large volume). Per-volume progress is
    # on the project's events; a clone failure surfaces there and must never fail the order
    # (fail_process! releases the project's private network).
    if result[:volume_clones].any?
      count = result[:volume_clones].count
      event.event_details.create!(
        data: "Restoring data into #{count} #{"volume".pluralize(count)} in the background. " \
              "Your services are available now; watch the project's events for restore progress.",
        event_code: "3f7c2b90a15de846"
      )
    end

    errors.empty?
  end

  ##
  # Passes over this order's containers before giving up on their network/IP.
  NETWORK_CHECK_PASSES = 3

  ##
  # Make sure every container this order created, and the project's SFTP containers, have
  # their private network and IP before anything is built.
  #
  # On 2026-10-20 two concurrent orders claimed the same network row; the loser's containers
  # were created with no network and no IP, and its order still completed. The claim is now
  # atomic, but the order no longer trusts it: EnsureContainerNetworkService repairs what is
  # missing, with a short inline retry for a network another worker is still creating.
  #
  # Only `result[:containers]` and SFTP containers created since this order started -- never
  # the project's pre-existing containers. An old broken container must not fail a new order
  # (the integrity sweep reports those).
  #
  # @return [Boolean] false (with one `errors` entry per container) when any is still not ready
  def ensure_container_networks!
    new_sftp = project.sftp_containers.active.where("deployment_sftps.created_at >= ?", @started_at).to_a
    pending = (result[:containers] + new_sftp).uniq
    reasons = {}

    NETWORK_CHECK_PASSES.times do |pass|
      break if pending.empty?
      sleep 2 if pass > 0
      pending = pending.select do |container|
        service = NetworkServices::EnsureContainerNetworkService.new(container, event)
        status = service.perform
        if status == :ready
          reasons.delete(container)
          false
        else
          reasons[container] = service.reason.presence || "Container #{container.name} is missing its private network or IP address."
          # Nothing to gain from asking again about a :failed container.
          status == :retry
        end
      end
    end

    reasons.each_value { |reason| errors << reason }
    reasons.empty?
  end

  def valid?
    return false unless valid_keys?
    if order.user.nil?
      errors << "Missing user"
      return false
    end
    unless order.user.active
      errors << "User is suspended"
      order.update_attribute :status, "cancelled"
      return false
    end
    unless order.can_process?
      errors << "Invalid order status"
      return false
    end
    if order.location.nil?
      errors << "Missing region"
      return false
    end
    if region.nil?
      errors << "Missing Availability Zone"
      return false
    end
    true
  end

  def valid_keys?
    unless order.data[:project]
      errors << "Missing project"
      return false
    end
    if order.deployment.nil? && order.data.dig(:project, :name).nil?
      errors << "Missing project name"
      return false
    end
    true
  end

  ##
  # Final management

  ##
  # Fail the order and record why, every time.
  #
  # The reason goes on the event (detail 1adee2a19e284b32) AND on the order itself as
  # `order_data["failure_reason"]`. The order is the durable record: a failed order's project
  # may later be deleted, which detaches the order and leaves the project's events to be
  # pruned, while orders are kept.
  def fail_process!(msg = nil)
    lines = errors.empty? ? [msg.presence || "Unknown failure"] : errors.map(&:to_s)
    lines << "#{@fatal_error.class}: #{@fatal_error.message}" if @fatal_error
    event.event_details.create!(
      data: "ProcessOrderService error output:\n\n#{lines.join("\n")}",
      event_code: "1adee2a19e284b32"
    )
    event.fail! msg
    # `order.data` is a copy, so write order_data directly. Saved by fail!'s update_attribute,
    # in the same write as the status.
    order.order_data = (order.order_data || {}).merge("failure_reason" => lines.join("; ").truncate(1_000))
    order.fail!

    release_network!
  end

  ##
  # Return the project's private network to the free pool -- but only once it is actually off
  # the node.
  #
  # Detaching the row (`deployment: nil`) is not on its own a release: the row stays `active`,
  # and `active` is what keeps it out of `GenerateProjectNetworkService`'s allocation pool.
  # `TrashBridgeNetworkService` is what removes the docker network and then clears `active`,
  # and it declines while the network still has addresses in use or a node cannot confirm the
  # removal. Whatever it declines is picked up by the ten-minute
  # `NetworkWorkers::PrivateNetCleanupWorker` sweep instead.
  #
  # Queried, NOT read through `project.private_network`. That `has_one` is loaded and cached
  # as nil before the network exists -- `GenerateProjectNetworkService#perform` reads it to
  # decide whether to allocate at all, and `@inherited_network_id` above reads it too -- and
  # binding the row sets the `belongs_to` on the Network without touching the project's cached
  # side (there is no `inverse_of` between them). So by failure time the association still
  # answers nil for a network this order allocated minutes earlier, and every failure before
  # `finalize!` (which happens to call `project.reload`) would release nothing: the row stays
  # bound to a dead project, inactive, retried by nobody, and goes into the allocation pool
  # with its docker network still on the node the moment the project is deleted.
  #
  # Never raises: this runs on the failure path, including from `perform`'s `ensure`.
  def release_network!
    return if project.nil? || project.id.nil?

    net = Network.find_by(deployment_id: project.id)
    return if net.nil?
    # Not ours to release -- the project came in with it. See @inherited_network_id.
    return if net.id == @inherited_network_id

    # `active: true` before the detach, deliberately. The allocation pool is "inactive AND no
    # deployment", so detaching a row that is already inactive -- which is exactly the state a
    # network whose create failed is in -- puts it in the pool BEFORE anything has established
    # that it is off the node. Marking it active first means "unconfirmed, do not reuse", and
    # it is TrashBridgeNetworkService that clears the flag once every node says the network is
    # gone. It also puts the row in `child_networks.active`, which is the set the ten-minute
    # PrivateNetCleanupWorker sweep retries; a detached inactive row is retried by nothing.
    net.update active: true, deployment: nil
    NetworkServices::TrashBridgeNetworkService.new(net).perform
  rescue => e
    ExceptionAlertService.new(e, "1adee2a19e284b32").perform
  end

  def complete_process!
    unless errors.empty?
      event.event_details.create!(
        data: "ProcessOrderService error output:\n\n#{errors.join("\n")}",
        event_code: "a0e582f298a0ca01"
      )
    end
    ProcessAppEventWorker.perform_async "NewOrder", order.user&.global_id, order.global_id
    event.done!
    order.done!
  end
end
