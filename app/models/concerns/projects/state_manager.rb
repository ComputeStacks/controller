module Projects
  module StateManager
    extend ActiveSupport::Concern

    # Return a string with the current status
    #
    # * working
    # * alert <-- most recent job failed
    # * ok
    # * deleting
    def current_state
      return 'deleting' if trashed? || deleting?
      return 'working' if working?
      return 'alert' if has_failed_jobs? # TODO: Ignore failed backup jobs if container is not running
      return 'alert' if provisioning_failed?
      return 'unhealthy' unless healthy?
      return 'warning' if has_active_alerts?
      'ok'
    end

    def working?
      event_logs.running.exists?
    end

    def has_active_alerts?
      alert_notifications.active.exists?
    end

    ##
    # Identifying Trash Status

    # Deleting checks events (used in admin)
    def deleting?
      event_logs.active.where(event_code: '20cd984da4da8963').exists?
    end

    # Trashed is used for end-users to hide state
    def trashed?
      status == 'deleting'
    end

    def mark_trashed!
      update status: 'deleting'
    end

    # Track the most recent provisioning attempt.
    def provisioning_failed?
      return false unless event_logs.where(locale: 'order.provision').exists?
      event_logs.where(locale: 'order.provision').order(created_at: :desc).first.failed?
    end

    # Most recent event failed
    def has_failed_jobs?
      last_event = event_logs.sorted.first
      return false if last_event.nil?
      return false if last_event.cancelled? # Cancelled events != failing!
      !last_event.success? && !last_event.active?
    end

    def healthy?
      services.each do |i|
        return false unless i.healthy?
      end
      true
    end

  end
end
