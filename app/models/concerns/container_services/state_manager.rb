module ContainerServices
  module StateManager
    extend ActiveSupport::Concern

    # Current Service State
    #
    # * working
    # * alert <-- most recent job failed
    # * resource_usage - cpu/mem usage is too high
    # * unhealthy - containers with failed healtchecks
    # * offline_containers -- not all containers are running
    # * online
    # * inactive
    def current_state
      return 'working' if working?
      return 'alert' if has_failed_jobs?
      return 'alert' if provisioning_failed?
      return 'active_alert' if has_active_alerts?
      return 'unhealthy' unless healthy?
      return 'offline_containers' unless all_containers_online?
      return 'resource_usage' unless resources_ok?
      active? ? 'online' : 'inactive'
    end

    def working?
      event_logs.active.exists?
    end

    # Most recent event failed
    def has_failed_jobs?
      last_event = event_logs.sorted.first
      return false if last_event.nil?
      last_event.failed?
    end

    def all_containers_online?
      containers.where(req_state: 'active').each do |i|
        return false unless i.running?
      end
      true
    end

    # Track the most recent provisioning attempt.
    def provisioning_failed?
      return false unless event_logs.where(locale: 'order.provision').exists?
      event_logs.where(locale: 'order.provision').order(created_at: :desc).first.failed?
    end

    def active?
      containers.where(req_state: 'running').exists?
    end

    ##
    # Prometheus
    def resources_ok?
      containers.each do |i|
        return false unless i.resources_ok?
      end
      true
    end

    def healthy?
      containers.each do |i|
        return false unless i.healthy?
      end
      true
    end

    ##
    # Active Alerts?
    def has_active_alerts?
      alert_notifications.active.exists?
    end

  end
end
