class ProcessOrderService

  attr_accessor :order,
                :event,
                :project,
                :container_service, # The created service
                :result,
                :errors

  def initialize(order)
    self.order = order
    self.event = order.current_event
    self.project = order.deployment if order.deployment
    self.errors = []

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
      fail_process! 'Invalid order parameters'
      return false
    end
    order.processing!
    unless within_quota?
      fail_process! 'Over quota'
      return false
    end
    if order.requires_project? && !init_project!
      fail_process! 'Failed to find or create project'
      return false
    end

    to_provision = order.data[:raw_order]
    loop_end = 3.minutes.from_now
    loop do
      break if to_provision.empty?
      break if loop_end <= Time.now
      to_provision.each_with_index do |product,index|
        base_job = case product[:product_type]
                   when 'container'
                     OrderServices::ContainerServiceOrderService
                   else
                     nil
                   end
        next if base_job.nil?

        job = base_job.new( order, event, project, product )

        # Keep pushing the result forward so each cycle can track what's been done so far.
        job.provision_state = result

        next unless job.ready_to_provision?

        job_status = job.perform
        job.errors.each do |err|
          errors << err
        end

        # Combine results hash so the next cycle will have it.
        self.result.merge!(job.result) do |k,a,b|
          a + b
        end

        # If it fails, but for some reason does not provide errors,
        # make sure we capture that and stop the order process from finalizing
        errors << "Failed to build product" if job.errors.empty? && !job_status

        # Remove this from the stack
        to_provision.delete_at index
      end
      break unless errors.empty?
      sleep 2
    end
    unless to_provision.empty? && errors.empty?
      fail_process! "Failed to provision all resources"
      return false
    end
    unless finalize!
      fail_process! 'Error on order cleanup'
      return false
    end
    complete_process!
    true
  ensure
    # If this is triggered and the event is still running, then something bad happened.
    if event.running?
      fail_process! 'Fatal Error'
    end
  end

  private

  def within_quota?
    requested_containers = 0
    order.data[:raw_order].each do |i|
      next unless i[:product_type] == 'container'
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
          event_code: 'b1f2ff50217bd39e'
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
          data: "Failed to create project: #{d.errors.full_messages.join(' ')}",
          event_code: '30dba49646cfd9f4'
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
    # Setup Metadata Token
    metadata_token = ProjectServices::GenMetadataToken.new(project)
    unless metadata_token.perform
      metadata_token.errors.each do |er|
        errors << er
      end
      return false
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

    # Actually provision the resources on the compute resources
    resource_provisioner = DeployServices::DeployProjectService.new(project, event)
    resource_provisioner.volume_clones = result[:volume_clones]
    unless resource_provisioner.perform
      errors << "Failed to provision resources"
      resource_provisioner.errors.each do |er|
        errors << er
      end
    end

    errors.empty?
  end

  def valid?
    return false unless valid_keys?
    if order.user.nil?
      errors << "Missing user"
      return false
    end
    unless order.user.active
      errors << "User is suspended"
      order.update_attribute :status, 'cancelled'
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

  def fail_process!(msg = nil)
    event.event_details.create!(
      data: "ProcessOrderService error output:\n\n#{errors.join("\n")}",
      event_code: "1adee2a19e284b32"
    ) unless errors.empty?
    event.fail! msg
    order.fail!
  end

  def complete_process!
    event.event_details.create!(
      data: "ProcessOrderService error output:\n\n#{errors.join("\n")}",
      event_code: "a0e582f298a0ca01"
    ) unless errors.empty?
    ProcessAppEventWorker.perform_async 'NewOrder', order.user&.global_id, order.global_id
    event.done!
    order.done!
  end

end
