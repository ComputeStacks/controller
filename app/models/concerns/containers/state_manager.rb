module Containers
  module StateManager
    extend ActiveSupport::Concern

    def current_state
      return 'migrating' if migrating?
      return 'starting' if starting?
      return 'stopping' if stopping?
      return 'working' if working?
      return 'alert' if has_failed_jobs?
      return 'resource_usage' unless resources_ok?
      stopped? ? 'offline' : 'online'
    rescue
      ''
    end

    ##
    # Should this container be online?

    def active?
      req_state == 'running'
    end

    def set_active!
      update req_state: 'running'
    end

    def set_inactive!
      update req_state: 'stopped'
    end

    ##
    # Uses Docker Client for real values
    def built?
      !docker_client(true).nil?
    end

    # Determine if the container is running.
    #
    # Default (direct = false) will use Prometheus,
    # otherwise it will directly query for the container within Docker.
    def running?(direct = false)
      return metric_last_seen > 1.minute.ago unless metric_last_seen.nil? || direct
      c = docker_client(true)
      return false if c.nil?
      c.info['State']['Running']
    end

    def stopped?
      !running?
    end

    ##
    # Uses events
    def starting?
      event_logs.starting.active.exists?
    end

    def stopping?
      event_logs.stopping.active.exists?
    end

    def working?
      event_logs.active.exists?
    end

    # Most recent event failed
    def has_failed_jobs?
      last_event = event_logs.sorted.first
      last_event.nil? ? false : last_event.failed?
    end

    def migrating?
      status == 'migrating'
    end

    def set_is_migrating!
      update status: 'migrating' unless migrating?
    end

    def resources_ok?
      s = stats
      return true if s.nil?
      return false if s[:cpu] > 85
      return false if s[:mem] > 88
      true
    end

    def restore_in_progress?
      event_logs.active.where(event_code: "agent-bde07117ae85937d").exists?
    end

  end
end
