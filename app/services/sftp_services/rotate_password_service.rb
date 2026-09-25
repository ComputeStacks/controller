module SftpServices
  ##
  # Replace an SFTP (bastion) container's SSH password and rebuild it.
  #
  # The password is only applied when the container is created (it is the image's `Cmd`),
  # so a new one takes effect once the rebuild completes. Open SSH, SFTP, and cloud shell
  # sessions are disconnected by the rebuild.
  #
  # The new password is committed *before* the rebuild is enqueued -- the worker reads it
  # from the database, so it must not sit in an open transaction. If the rebuild is
  # refused or cancelled, the previous password is restored.
  #
  # @!attribute sftp
  #   @return [Deployment::Sftp]
  # @!attribute audit
  #   @return [Audit]
  # @!attribute errors
  #   @return [Array<String>]
  # @!attribute event
  #   The rebuild event, set on success.
  #   @return [EventLog]
  #
  class RotatePasswordService
    attr_accessor :sftp, :audit, :errors, :event

    # @param [Deployment::Sftp] sftp
    # @param [Audit] audit
    def initialize(sftp, audit)
      self.sftp = sftp
      self.audit = audit
      self.errors = []
      self.event = nil
    end

    # @return [Boolean]
    def perform
      return false unless preconditions_met?

      old_password = sftp.password_encrypted
      sftp.update!(password: Deployment::Sftp.generate_password)

      power = PowerCycleContainerService.new(sftp, "rebuild", audit)
      result = power.perform

      # PowerCycle cancels (but still returns true) when another action is in progress,
      # so a true result alone does not mean the rebuild will run.
      unless result && power.event&.pending?
        restore_password!(old_password)
        self.errors = power.errors.dup
        errors << "Unable to rebuild the SSH container." if errors.empty?
        return false
      end

      self.event = power.event
      event.event_details.create!(
        data: "SSH password rotated.",
        event_code: "78107ee60304a54c"
      )
      true
    end

    private

    # Put back the previous password, but only if the row still holds the one this call
    # wrote -- a concurrent rotation may have replaced it since.
    #
    # @param [String] old_password encrypted value
    def restore_password!(old_password)
      Deployment::Sftp.where(id: sftp.id, password_encrypted: sftp.password_encrypted)
        .update_all(password_encrypted: old_password)
      sftp.reload
    end

    # Checked before anything is changed.
    #
    # @return [Boolean]
    def preconditions_met?
      if sftp.deployment.nil?
        errors << "SSH container no longer belongs to a project."
      elsif sftp.to_trash
        errors << "SSH container is being deleted."
      elsif sftp.node.nil? || !sftp.node.online?
        errors << "The node hosting this SSH container is offline."
      elsif sftp.event_logs.active.exists?
        errors << "Another action is in progress on this SSH container; try again shortly."
      end
      errors.empty?
    end
  end
end
