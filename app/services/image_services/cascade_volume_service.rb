module ImageServices
  ##
  # Apply an image volume parameter to every already-deployed service of that image.
  #
  # This is the single dispatch point shared by all four entry points (the "cascade"
  # checkbox on the create form and the retroactive "apply to existing services" action,
  # each of which exists in both the admin and the non-admin namespace). The authorization
  # decision lives here so that no caller can forget it: cascading mutates *other* users'
  # running services, so it is admin-only regardless of who owns the image.
  #
  # Nothing is rebuilt or restarted. The worker attaches the volume to each service's
  # config so that it lands on that service's next natural rebuild.
  #
  # @!attribute volume_param
  #   @return [ContainerImage::VolumeParam]
  # @!attribute current_user
  #   @return [User] who requested the cascade
  # @!attribute remote_ip
  #   @return [String] for the audit record
  # @!attribute errors
  #   @return [Array<String>] why we declined
  #
  class CascadeVolumeService
    EVENT_CODE = "91c08ca8a3617fbc".freeze

    attr_accessor :volume_param,
      :current_user,
      :remote_ip,
      :errors

    # @param [ContainerImage::VolumeParam] volume_param
    # @param [User] current_user
    # @param [String] remote_ip
    def initialize(volume_param, current_user, remote_ip)
      self.volume_param = volume_param
      self.current_user = current_user
      self.remote_ip = remote_ip
      self.errors = []
    end

    ##
    # Create the audit + event log and dispatch the cascade worker.
    #
    # @return [EventLog, nil] nil when we declined; `errors` says why.
    def perform
      return nil unless valid?

      image = volume_param.container_image
      audit = Audit.create_from_object!(image, "updated", remote_ip, current_user)
      event = EventLog.create!(
        locale: "image.cascade_volume",
        locale_keys: {"image" => image.name},
        event_code: EVENT_CODE,
        status: "pending",
        audit: audit
      )
      event.container_images << image
      ImageWorkers::CascadeVolumeChangeWorker.perform_async(volume_param.id, event.id)
      event
    end

    private

    # @return [Boolean]
    def valid?
      unless volume_param.is_a?(ContainerImage::VolumeParam) && volume_param.persisted?
        errors << "Unknown volume."
        return false
      end
      unless current_user.is_a?(User) && current_user.is_admin?
        errors << "Only administrators may apply a volume to existing services."
        return false
      end
      if volume_param.source_volume.present?
        errors << "Mounted volumes cannot be applied to existing services."
        return false
      end
      true
    end
  end
end
