module VolumeServices
  ##
  # =Mount detector
  #
  # Clear `Volume#awaiting_mount` for every volume whose bind was actually included in the
  # container Docker just created, and tell the agent it may start backing those volumes up.
  #
  # Called from `Containerized#build!` — the single place a container is created — with the
  # bind list *that was sent to Docker* rather than a freshly-derived query. That is what makes
  # this exact and race-free: a volume attached microseconds after `runtime_config` was computed
  # is not in the payload, so it correctly stays pending until the next rebuild instead of being
  # marked mounted by a container that does not carry it.
  #
  # Two rules this class must never break, because it runs inside container provisioning:
  #
  #   1. *No network I/O.* `ContainerWorkers::ProvisionWorker` wraps the build in
  #      `Timeout.timeout(70)`. `Volume after_commit :update_consul!` performs a synchronous
  #      `Agent::Client#put_volume` with a 10s timeout, so a slow agent here would turn a
  #      successful build into `event.fail! "Fatal error"` with the container created but never
  #      started. Hence `update_columns` (no callbacks) plus
  #      `VolumeWorkers::UpdateDesiredStateWorker` for the out-of-band push.
  #   2. *Never raise.* Everything is rescued; a detector bug must not be able to break a build.
  #
  # @!attribute container
  #   @return [Deployment::Container]
  # @!attribute binds
  #   @return [Array<String>,nil] HostConfig.Binds as handed to Docker::Container.create
  # @!attribute event
  #   @return [EventLog,nil]
  class MarkVolumesMountedService
    # "<volumes> are now mounted and eligible for backups"
    MOUNTED_EVENT_CODE = "2b730c12fc572fc5"

    attr_accessor :container,
      :binds,
      :event

    # @param [Deployment::Container] container
    # @param [Array<String>,nil] binds
    # @param [EventLog,nil] event
    def initialize(container, binds, event)
      self.container = container
      self.binds = binds
      self.event = event
    end

    # @return [Boolean] true when at least one volume was flipped out of `awaiting_mount`.
    def perform
      names = volume_names
      return false if names.empty?

      # Volume names are UUIDs and globally unique (`validates :name, uniqueness: true`), so no
      # service/project scoping is needed or wanted here.
      cleared = Volume.awaiting_mount.where(name: names).to_a
      return false if cleared.empty?

      cleared.each do |volume|
        volume.update_columns(awaiting_mount: false)
        VolumeWorkers::UpdateDesiredStateWorker.perform_async volume.id
      end

      if event
        event.event_details.create!(
          data: "Volume mount is now live for #{container&.name}; backups enabled for: #{cleared.map { |v| "#{v.label} (#{v.name})" }.join(", ")}",
          event_code: MOUNTED_EVENT_CODE
        )
      end
      true
    rescue => e
      ExceptionAlertService.new(e, "0d38160e8304342f").perform
      false
    end

    private

    # Parse volume names out of the docker bind list.
    #
    # A bind is `"<volume-name>:<mount-path>:<rw|ro>"`. The mount path can itself contain a
    # colon in principle, so split from the LEFT and keep only the first segment. Anything that
    # is not a named volume — an absolute host path bind, a blank entry — is ignored.
    #
    # @return [Array<String>]
    def volume_names
      Array(binds).filter_map { |entry|
        name = entry.to_s.split(":", 2).first.to_s.strip
        next if name.blank?
        next if name.start_with?("/") # host path bind, not a named volume

        name
      }.uniq
    end
  end
end
