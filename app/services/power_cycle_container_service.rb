# Power management for a container.
#
#
# @!attribute action
#   @return [String] rebuild, restart, start, stop
# @!attribute audit
#   @return [Audit]
# @!attribute container
#   @return [Deployment::Container]
# @!attribute errors
#   @return [Array]
#
class PowerCycleContainerService

  attr_accessor :audit,
                :action,
                :container,
                :delay, # eg: 30.seconds
                :errors

  # @param [Deployment::Container] container
  # @param [String] action
  # @param [Audit] audit
  def initialize(container, action, audit)
    self.audit = audit
    self.container = container
    self.action = action
    self.delay = nil
    self.errors = []
  end

  # @return [Boolean]
  def perform
    event = EventLog.new(
      locale_keys: {
        label: container.is_a?(Deployment::Sftp) ? 'SFTP' : container.label,
        container: container.name
      },
      status: "pending"
    )
    event.audit = audit if audit

    self.action = 'rebuild' if %w(start restart).include?(action) && !container.built?

    case action
    when 'build'
      event.event_code = '3b6c028e41b0875b'
      event.locale = 'container.build'
    when 'rebuild'
      event.event_code = '14bbe1dc184afba0'
      event.locale = 'container.rebuild'
    when 'restart'
      event.event_code = 'd611b2bbf50bd48c'
      event.locale = 'container.restart'
    when 'start'
      event.event_code = 'f59498e7717c7106'
      event.locale = 'container.start'
    when 'stop'
      event.event_code = '0b264bd661e2d449'
      event.locale = 'container.stop'
    else
      event.event_code = '79eb562a7e6d5d61'
      event.locale = 'unknown'
    end

    unless event.save
      self.errors << "Fatal error setting up job."
      return false
    end

    if container.is_a?(Deployment::Container)
      event.containers << container unless event.containers.include? container
      event.container_services << container.service unless event.container_services.include? container.service
    elsif container.is_a?(Deployment::Sftp)
      event.sftp_containers << container unless event.sftp_containers.include? container
    end

    if container.deployment.nil?
      event.event_details.create!(
        data: "Error: Container no longer has a project.",
        event_code: 'e7842b49012cb980'
      )
      event.fail! 'Fatal error'
      return false
    end

    event.deployments << container.deployment unless event.deployments.include? container.deployment

    unless validate!
      event.event_details.create!(
        data: "Error: #{errors.join(' ')}",
        event_code: '79eb562a7e6d5d61'
      )
      event.fail! 'Fatal error'
      return false
    end

    if in_progress? event
      event.event_details.create!(
        data: "Action already in progress, please try again later.",
        event_code: '65a0ac3cf9131abb'
      )
      event.cancel! 'Action already in progress'
      return true
    end

    unless container.node.online?
      event.event_details.create!(
        data: "Node is offline, cancelling",
        event_code: '7f55ffc42c0dac14'
      )
      event.cancel! 'Node offline'
      return false
    end

    if container.is_a?(Deployment::Container)
      container.subscription.update_attribute(:active, true) if container.subscription && !container.subscription.active
    end

    # TODO: Find a way to test provisioning
    return true if Rails.env.test?

    if delay.nil?
      case action
      when 'build'
        ContainerWorkers::ProvisionWorker.perform_async container.to_global_id.to_s, event.to_global_id.to_s
      when 'rebuild'
        ContainerWorkers::RebuildWorker.perform_async container.to_global_id.to_s, event.to_global_id.to_s
      when 'restart'
        ContainerWorkers::RestartWorker.perform_async container.to_global_id.to_s, event.to_global_id.to_s
      when 'start'
        ContainerWorkers::StartWorker.perform_async container.to_global_id.to_s, event.to_global_id.to_s
      when 'stop'
        ContainerWorkers::StopWorker.perform_async container.to_global_id.to_s, event.to_global_id.to_s
      else
        return false
      end
    else
      case action
      when 'build'
        ContainerWorkers::ProvisionWorker.perform_in delay, container.to_global_id.to_s, event.to_global_id.to_s
      when 'rebuild'
        ContainerWorkers::RebuildWorker.perform_in delay, container.to_global_id.to_s, event.to_global_id.to_s
      when 'restart'
        ContainerWorkers::RestartWorker.perform_in delay, container.to_global_id.to_s, event.to_global_id.to_s
      when 'start'
        ContainerWorkers::StartWorker.perform_in delay, container.to_global_id.to_s, event.to_global_id.to_s
      when 'stop'
        ContainerWorkers::StopWorker.perform_in delay, container.to_global_id.to_s, event.to_global_id.to_s
      else
        return false
      end
    end
    true
  end

  private

  # @return [Boolean]
  def validate!
    unless container.is_a?(Deployment::Container) || container.is_a?(Deployment::Sftp)
      self.errors << "Unknown container"
    end
    unless %w(build rebuild restart start stop).include? action
      self.errors << "Unknown action. Only start, stop, rebuild, and restart are permitted"
    end
    self.errors.empty?
  end

  # @param [EventLog] event
  # @return [Boolean]
  def in_progress?(event)
    return true if container.event_logs.where.not(id: event.id).where(event_code: event.event_code).active.exists?
    return true if container.event_logs.where.not(id: event.id).starting.active.exists?
    return true if container.event_logs.where.not(id: event.id).stopping.active.exists?
    false
  end

end
