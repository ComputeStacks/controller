module UserWorkers
  ##
  # Retries the stops (suspension) or starts (reactivation) UserServices::ToggleActiveService
  # could not get accepted, against the containers the suspension recorded.
  #
  # Gives up quietly when a newer suspend/reactivate has happened (that one owns the
  # containers now), and after MAX_ATTEMPTS with a note on the toggle event naming what
  # it could not reach.
  class ReconcileSuspensionWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    INTERVAL = 1.minute
    MAX_ATTEMPTS = 30

    # @param [Integer] user_id
    # @param [Integer] toggle_event_id the suspend or reactivate EventLog
    # @param [Integer] attempt
    def perform(user_id, toggle_event_id, attempt)
      user = User.find_by(id: user_id)
      toggle_event = EventLog.find_by(id: toggle_event_id)
      return if user.nil? || toggle_event.nil?

      service = UserServices::ToggleActiveService
      return if service.toggle_events(user).where("event_logs.id > ?", toggle_event.id).exists?

      suspending = toggle_event.locale == "users.inactive"
      return if user.active == suspending # out of step with the user; a newer toggle is coming

      desired = suspending ? "stopped" : "running"
      action = suspending ? "stop" : "start"
      reasons = {}
      pending = service.recorded_containers(service.suspension_for(user, toggle_event)).select do |container|
        # Parked until the node's maintenance ends: that action will run, nothing to retry.
        next false if PowerCycleContainerService.parked_events_for(container).exists?
        if container.event_logs.active.exists? # let it finish, then look again
          reasons[container] = "another action in progress"
          next true
        end
        next false if container.req_state == desired
        # Unreachable: wait without trying, so retries leave no audit or event behind. A
        # node in maintenance is tried even when disconnected (rebooting): the action is
        # parked there and runs when it is back.
        if (reason = unreachable_reason(container))
          reasons[container] = reason
          next true
        end
        reasons[container] = "refused"
        !service.power_cycle!(container, action, toggle_event)
      end
      return if pending.empty?

      if attempt >= MAX_ATTEMPTS
        toggle_event.event_details.create!(
          data: "Unable to #{action} #{pending.map { |c| "#{c.name} (#{reasons[c]})" }.join(", ")}; giving up.",
          event_code: "6d1f0b8e2a4c9735"
        )
        return
      end
      self.class.perform_in(INTERVAL, user_id, toggle_event_id, attempt + 1)
    rescue => e
      ExceptionAlertService.new(e, "6d1f0b8e2a4c9735").perform
    end

    private

    # @return [String, nil] why the container can't be acted on right now
    def unreachable_reason(container)
      return "no project" if container.deployment.nil?
      return "no node" if container.node.nil?
      "node disconnected" if container.node.disconnected && !container.node.maintenance
    end
  end
end
