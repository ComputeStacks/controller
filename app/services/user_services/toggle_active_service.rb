module UserServices
  ##
  # Activate/Deactivate Users
  #
  # Suspension stops the user's containers that are meant to be running and records them
  # on its event (labels["suspended_containers"]) BEFORE stopping anything; reactivation
  # starts exactly the containers its most recent suspension recorded. Containers the user
  # had stopped themselves stay stopped.
  #
  # A stop or start that is refused (node offline, another action in progress) is retried
  # by UserWorkers::ReconcileSuspensionWorker against the recorded intent, so a refusal or
  # a quick suspend/reactivate never strands a container in the wrong state.
  #
  # @!attribute user
  #   @return [User]
  # @!attribute event
  #   @return [EventLog]
  class ToggleActiveService
    SUSPENDED_CONTAINERS_LABEL = "suspended_containers"
    EVENT_CODE = "5e3f927694e5ae34"

    attr_accessor :user,
      :event

    # @param [User] user
    # @param [Audit] audit
    def initialize(user, audit)
      self.user = user
      build_event(audit)
    end

    def perform
      event.start!
      user.active ? activate_user! : suspend_user!
      event.done!
      true
    rescue => e
      ExceptionAlertService.new(e, "653f400954df1fe3").perform
      event.event_details.create!(data: e.message, event_code: "653f400954df1fe3")
      event.fail! "Fatal Error"
      # Finish whatever the failure interrupted from the recorded intent.
      reconcile_later!
      false
    end

    # The suspension event whose recorded containers apply to `toggle_event`: the event
    # itself for a suspension, the latest suspension before it for a reactivation.
    #
    # @param [User] user
    # @param [EventLog] toggle_event
    # @return [EventLog, nil]
    def self.suspension_for(user, toggle_event)
      return toggle_event if toggle_event.locale == "users.inactive"
      toggle_events(user).where(locale: "users.inactive").where("event_logs.id < ?", toggle_event.id)
        .order(id: :desc).first
    end

    # @return [ActiveRecord::Relation] the user's suspend/reactivate events
    def self.toggle_events(user)
      EventLog.joins(:users).where(users: {id: user.id}).where(event_code: EVENT_CODE)
    end

    # @param [EventLog, nil] suspension
    # @return [Array] the recorded containers that still exist
    def self.recorded_containers(suspension)
      Array(suspension&.labels&.dig(SUSPENDED_CONTAINERS_LABEL)).filter_map do |gid|
        GlobalID::Locator.locate(gid)
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end

    # Request `action` on `container` under its own audit, so PowerCycleContainerService
    # builds its own event instead of adopting (and later finishing) the toggle's event.
    #
    # @return [Boolean] whether the action was accepted: queued now, or parked until the
    #   node's maintenance ends. False when it was refused or canceled.
    def self.power_cycle!(container, action, toggle_event)
      audit = Audit.create_from_object!(container, "updated", toggle_event.audit&.ip_addr, toggle_event.audit&.user)
      service = PowerCycleContainerService.new(container, action, audit)
      service.perform && service.event.present? && service.event.reload.pending?
    end

    private

    def build_event(audit)
      self.event = EventLog.create!(
        locale: "users.#{user.active ? "active" : "inactive"}",
        locale_keys: {user: user.full_name},
        status: "pending",
        audit: audit,
        event_code: EVENT_CODE
      )
      event.users << user
      nil
    end

    def activate_user!
      user.deployed_containers.each do |container|
        container.subscription.unpause! if container.subscription
      end
      containers = self.class.recorded_containers(self.class.suspension_for(user, event))
      refused = containers.reject { |c| self.class.power_cycle!(c, "start", event) }
      reconcile_later! if refused.any?
      ProcessAppEventWorker.perform_async "UserActivated", nil, user.global_id
    end

    def suspend_user!
      containers = containers_to_stop
      # Record first: whatever happens below, reactivation knows what to restart.
      event.update!(labels: event.labels.merge(SUSPENDED_CONTAINERS_LABEL => containers.map { |c| c.global_id.to_s }))
      unless user.user_group.bill_suspended
        user.deployed_containers.each do |container|
          container.subscription.pause! if container.subscription
        end
      end
      refused = containers.reject { |c| self.class.power_cycle!(c, "stop", event) }
      reconcile_later! if refused.any?
      ProcessAppEventWorker.perform_async "UserSuspended", nil, user.global_id
    end

    # Containers meant to be running: req_state "running", plus any the last reactivation
    # set out to start whose start has not landed yet (queued, parked, or being retried,
    # so req_state still reads "stopped") -- unless someone has stopped it since.
    def containers_to_stop
      all = user.deployed_containers.to_a + user.sftp_containers.to_a
      reactivation = self.class.toggle_events(user).where(locale: "users.active")
        .where("event_logs.id < ?", event.id).order(id: :desc).first
      restarting = reactivation ? self.class.recorded_containers(self.class.suspension_for(user, reactivation)) : []
      all.select do |c|
        next true if c.req_state == "running"
        restarting.include?(c) && !c.event_logs.stopping.where("event_logs.id > ?", reactivation.id).exists?
      end
    end

    # At most once per toggle, however the toggle ended.
    def reconcile_later!
      return if @reconcile_scheduled
      @reconcile_scheduled = true
      UserWorkers::ReconcileSuspensionWorker.perform_in(UserWorkers::ReconcileSuspensionWorker::INTERVAL, user.id, event.id, 1)
    end
  end
end
