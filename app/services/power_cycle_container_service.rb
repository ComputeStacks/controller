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
# @!attribute [r] outcome
#   @return [Symbol, nil] what #perform did: :queued, :deferred (parked for maintenance),
#     :in_progress (another action is running; event canceled), :refused_offline (no node,
#     or node offline), or :failed. Set on every return path of #perform.
#
class PowerCycleContainerService
  attr_accessor :audit,
    :action,
    :container,
    :event,
    :delay, # eg: 30.seconds
    :errors,
    :callback_auth,
    :callback_url,
    :supersede # false for automatic recovery, which must never replace a parked request

  attr_reader :outcome

  # @param [Deployment::Container] container
  # @param [String] action
  # @param [Audit] audit
  def initialize(container, action, audit)
    self.audit = audit
    self.container = container
    self.action = action
    self.delay = nil
    self.event = nil
    self.errors = []
    self.callback_auth = nil
    self.callback_url = nil
    self.supersede = true
    @outcome = nil
  end

  # @return [Boolean]
  def perform
    self.action = "rebuild" if %w[start restart].include?(action) && !container.built?

    self.event = audit.event_logs.first if audit && audit.event_logs.count == 1
    # Several containers acting under one audit share its event, but a parked event can
    # only carry one container: the next container gets an event of its own. Nor is an
    # event an earlier container already ended (canceled, failed) reused: this action
    # would be attached to it and never run.
    self.event = nil if event && (parked_for_another_container?(event) || !event.active?)
    build_event! if event.nil?
    return failed! unless errors.empty? # Errors could be added by build_event

    if container.is_a?(Deployment::Container)
      event.containers << container unless event.containers.include? container
      event.container_services << container.service unless event.container_services.include? container.service
    elsif container.is_a?(Deployment::Sftp)
      event.sftp_containers << container unless event.sftp_containers.include? container
    end

    if container.deployment.nil?
      event.event_details.create!(
        data: "Error: Container no longer has a project.",
        event_code: "e7842b49012cb980"
      )
      event.fail! "Fatal error"
      return failed!
    end

    event.deployments << container.deployment unless event.deployments.include? container.deployment

    unless validate!
      event.event_details.create!(
        data: "Error: #{errors.join(" ")}",
        event_code: "79eb562a7e6d5d61"
      )
      event.fail! "Fatal error"
      return failed!
    end

    if container.node.nil?
      event.event_details.create!(
        data: "Container has no node, cancelling",
        event_code: "7f55ffc42c0dac14"
      )
      event.cancel! "Container has no node", code: "node_offline"
      @outcome = :refused_offline
      return false
    end

    # The latest request wins: a parked action for this container is replaced, never left
    # to block this one and then run after it.
    # (Unless something else is genuinely in progress, which refuses this request anyway.)
    supersede_parked! if supersede && !in_progress?(event, ignoring_parked: true)

    if in_progress? event
      event.event_details.create!(
        data: "Action already in progress, please try again later.",
        event_code: "65a0ac3cf9131abb"
      )
      event.cancel! "Action already in progress"
      @outcome = :in_progress
      return true
    end

    # A node in maintenance takes no container work, and may be rebooting. Park the event
    # (still pending) and let ContainerWorkers::DeferredPowerWorker run it once the node is
    # back online, so a restart that applies an already-saved change is not lost.
    if container.node.maintenance
      defer_for_maintenance!
      @outcome = :deferred
      return true
    end

    unless container.node.online?
      event.event_details.create!(
        data: "Node is offline, cancelling",
        event_code: "7f55ffc42c0dac14"
      )
      event.cancel! "Node offline", code: "node_offline"
      @outcome = :refused_offline
      return false
    end

    # Not on a stop: a suspension pauses the subscription, and its stop may run later
    # (parked for maintenance), so a stop must never switch billing back on.
    if container.is_a?(Deployment::Container) && action != "stop" && !container.owner_suspended?
      container.subscription.update_attribute(:active, true) if container.subscription && !container.subscription.active
    end

    @outcome = :queued
    # TODO: Find a way to test provisioning
    return true if Rails.env.test?

    if delay.nil?
      case action
      when "build"
        ContainerWorkers::ProvisionWorker.perform_async container.global_id, event.global_id
      when "rebuild"
        ContainerWorkers::RebuildWorker.perform_async container.global_id, event.global_id
      when "restart"
        ContainerWorkers::RestartWorker.perform_async container.global_id, event.global_id
      when "start"
        ContainerWorkers::StartWorker.perform_async container.global_id, event.global_id
      when "stop"
        ContainerWorkers::StopWorker.perform_async container.global_id, event.global_id
      else
        return failed!
      end
    else
      case action
      when "build"
        ContainerWorkers::ProvisionWorker.perform_in delay, container.global_id, event.global_id
      when "rebuild"
        ContainerWorkers::RebuildWorker.perform_in delay, container.global_id, event.global_id
      when "restart"
        ContainerWorkers::RestartWorker.perform_in delay, container.global_id, event.global_id
      when "start"
        ContainerWorkers::StartWorker.perform_in delay, container.global_id, event.global_id
      when "stop"
        ContainerWorkers::StopWorker.perform_in delay, container.global_id, event.global_id
      else
        return failed!
      end
    end
    true
  end

  private

  # @return [false]
  def failed!
    @outcome = :failed
    false
  end

  DEFERRED_ACTION_LABEL = "deferred_action"
  DEFERRED_NODE_LABEL = "deferred_node_id"
  DEFERRED_CONTAINER_LABEL = "deferred_container"

  # @return [ActiveRecord::Relation] pending events parked for this container
  def self.parked_events_for(container)
    EventLog.where(status: "pending")
      .where("labels ->> ? = ?", DEFERRED_CONTAINER_LABEL, container.global_id.to_s)
  end

  def parked_for_another_container?(evt)
    parked = evt.labels[DEFERRED_CONTAINER_LABEL]
    parked.present? && parked != container.global_id.to_s
  end

  def supersede_parked!
    self.class.parked_events_for(container).where.not(id: event.id).find_each do |parked|
      parked.event_details.create!(
        data: "Superseded by a later #{action} request.",
        event_code: "3c9f1a6e0b7d2458"
      )
      parked.cancel! "Superseded", code: "superseded"
    end
  end

  def defer_for_maintenance!
    event.update!(labels: event.labels.merge(
      DEFERRED_ACTION_LABEL => action,
      DEFERRED_NODE_LABEL => container.node.id.to_s,
      DEFERRED_CONTAINER_LABEL => container.global_id.to_s
    ))
    event.event_details.create!(
      data: "The node is in maintenance; this #{action} will run when maintenance ends.",
      event_code: "5b0e7c2d94a1f638"
    )
  end

  def build_event!
    self.event = EventLog.new(
      locale_keys: {
        label: container.is_a?(Deployment::Sftp) ? "SFTP" : container.label,
        container: container.name
      },
      status: "pending"
    )
    event.audit = audit if audit

    case action
    when "build"
      event.event_code = "3b6c028e41b0875b"
      event.locale = "container.build"
    when "rebuild"
      event.event_code = "14bbe1dc184afba0"
      event.locale = "container.rebuild"
    when "restart"
      event.event_code = "d611b2bbf50bd48c"
      event.locale = "container.restart"
    when "start"
      event.event_code = "f59498e7717c7106"
      event.locale = "container.start"
    when "stop"
      event.event_code = "0b264bd661e2d449"
      event.locale = "container.stop"
    else
      event.event_code = "79eb562a7e6d5d61"
      event.locale = "unknown"
    end

    unless callback_url.blank?
      event.labels["callback_url"] = callback_url
      event.labels["callback_auth"] = callback_auth
    end

    unless event.save
      errors << "Fatal error setting up job."
    end
  end

  # @return [Boolean]
  def validate!
    unless container.is_a?(Deployment::Container) || container.is_a?(Deployment::Sftp)
      errors << "Unknown container"
    end
    unless %w[build rebuild restart start stop].include? action
      errors << "Unknown action. Only start, stop, rebuild, and restart are permitted"
    end
    errors.empty?
  end

  # @param [EventLog] event
  # @param [Boolean] ignoring_parked leave out events parked for maintenance
  # @return [Boolean]
  def in_progress?(event, ignoring_parked: false)
    others = container.event_logs.where.not(id: event.id)
    others = others.where("event_logs.labels ->> ? IS NULL", DEFERRED_CONTAINER_LABEL) if ignoring_parked
    return true if others.where(event_code: event.event_code).active.exists?
    return true if others.starting.active.exists?
    return true if others.stopping.active.exists?
    false
  end
end
