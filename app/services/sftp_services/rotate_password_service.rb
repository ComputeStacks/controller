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
  # refused or canceled, the previous password is restored.
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
  # @!attribute callback_url
  #   Optional; notified when the rebuild event finishes (see Events::StateManager).
  #   @return [String]
  # @!attribute callback_auth
  #   @return [String]
  # @!attribute [r] error_code
  #   Set when refused because of the node: "node_maintenance", or "node_offline" (also
  #   when the container has no node). nil for any other refusal.
  #   @return [String, nil]
  #
  class RotatePasswordService
    attr_accessor :sftp, :audit, :errors, :event, :callback_url, :callback_auth
    attr_reader :error_code

    # @param [Deployment::Sftp] sftp
    # @param [Audit] audit
    def initialize(sftp, audit)
      self.sftp = sftp
      self.audit = audit
      self.errors = []
      self.event = nil
      self.callback_url = nil
      self.callback_auth = nil
      @error_code = nil
    end

    # @return [Boolean]
    def perform
      return false unless preconditions_met?

      # Read the previous password under the row lock, not from the copy loaded with the
      # request -- a concurrent rotation may have committed since, and restoring a stale
      # value would roll back a rebuild that is still going ahead.
      old_password = nil
      sftp.with_lock do
        old_password = sftp.password_encrypted
        sftp.update!(password: Deployment::Sftp.generate_password)
      end

      power = PowerCycleContainerService.new(sftp, "rebuild", audit)
      power.callback_url = callback_url
      power.callback_auth = callback_auth
      result = power.perform

      # PowerCycle cancels (but still returns true) when another action is in progress,
      # so a true result alone does not mean the rebuild will run.
      unless result && power.event&.pending?
        restore_password!(old_password)
        # The node went offline between the precondition check and the rebuild.
        @error_code = Nodes::CustomerStatusPresenter.code_for("offline") if power.outcome == :refused_offline
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
        @error_code = Nodes::CustomerStatusPresenter.code_for(Nodes::CustomerStatusPresenter.state_for(sftp.node))
        errors << if sftp.node&.maintenance
          "The node hosting this SSH container is in maintenance; try again once it ends."
        else
          "The node hosting this SSH container is offline."
        end
      elsif sftp.event_logs.active.exists?
        errors << "Another action is in progress on this SSH container; try again shortly."
      end
      errors.empty?
    end
  end
end
