module VolumeWorkers
  ##
  # Push one volume's desired-state to its node's cs-agent, out of band.
  #
  # Exists so that clearing `awaiting_mount` never performs network I/O on the container
  # provisioning path. `VolumeServices::MarkVolumesMountedService` runs inside
  # `Containerized#build!`, which `ContainerWorkers::ProvisionWorker` wraps in
  # `Timeout.timeout(70)`; `Volume after_commit :update_consul!` would put a 10s HTTP call to
  # the agent in there, so the detector uses `update_columns` (no callbacks) and enqueues this
  # instead. This is where `backup: true` finally reaches the agent.
  class UpdateDesiredStateWorker
    include Sidekiq::Worker

    # Raised only to hand a failed PUT back to Sidekiq's retry.
    class PushFailed < StandardError; end

    # retry: 10 spans roughly a day of Sidekiq's exponential backoff, and that width is the
    # point. If every attempt is exhausted, nothing else reconciles the divergence: the DB says
    # mounted-and-borg-enabled while the agent still holds `backup: false`, and the volume is
    # simply never scheduled for a backup. The known self-heals do not cover it —
    # `RegionWorkers::VolumeUsageWorker` writes with `update_columns` (no callbacks), and the
    # start/stop/restart workers only re-push when a container actually changes power state,
    # which `ContainerWorkers::ProvisionWorker` skips entirely for a container rebuilt into a
    # stopped state. A node can be unreachable for hours, so the retry window has to outlast it;
    # the PUT is an idempotent upsert, so repeating it costs nothing.
    sidekiq_options retry: 10, queue: "dep_low"

    # Last line of defence: make an exhausted retry chain visible in the app's own alerting
    # rather than only in Sidekiq's dead set, because the symptom otherwise is silence — a
    # volume that is simply never backed up.
    sidekiq_retries_exhausted do |msg, _e|
      volume_id = msg["args"].first
      volume = Volume.find_by(id: volume_id)
      SystemEvent.create!(
        message: "Volume #{volume_id} may not be scheduled for backups: the agent never accepted its desired-state",
        log_level: "warn",
        data: {
          volume: volume_id,
          volume_name: volume&.name,
          deployment: volume&.deployment_id,
          borg_enabled: volume&.borg_enabled,
          awaiting_mount: volume&.awaiting_mount,
          hint: "Re-push with Volume#update_consul!, or restart a container of the service."
        },
        event_code: "2ca3aeaffb5c902e"
      )
    end

    # @param volume_id [Integer] Volume#id (Sidekiq.strict_args! — an Integer, not a GlobalID)
    def perform(volume_id)
      volume = Volume.find_by id: volume_id
      return if volume.nil?
      return if volume.to_trash

      # `Volumes::ConsulVolume#update_consul!` is transport-tolerant — Agent::Client#put_volume
      # returns false rather than raising — so a falsey result means the desired state, and with
      # it `backup: true`, never reached the agent, and the volume would sit unbacked-up until
      # something else happened to re-save it (potentially weeks). Raise so `retry: 3` is not
      # decoration; the PUT is an idempotent upsert, so repeating it costs nothing.
      raise PushFailed, "Unable to push desired-state for volume #{volume.id} to its agent" unless volume.update_consul!
    rescue PushFailed
      raise
    rescue => e
      ExceptionAlertService.new(e, "2ca3aeaffb5c902e").perform
    end
  end
end
