module SftpServices
  class ReloadSshKeysService

    attr_accessor :container,
                  :audit,
                  :event,
                  :result,
                  :errors

    def initialize(container, audit)
      self.container = container
      self.audit = audit
      self.result = []
      self.errors = []
      self.event = nil
    end

    def perform
      return false unless params_valid?
      build_event!
      event.start!
      ContainerWorkers::ContainerExecWorker.perform_async(
        container.to_global_id.to_s,
        event.to_global_id.to_s,
        %w(/usr/bin/ruby /usr/local/bin/load_ssh_keys.rb)
      )
    end

    private

    def build_event!
      self.event = EventLog.create!(
        locale_keys: { container: container.name },
        locale: 'sftp.reload_ssh_keys',
        status: "pending",
        audit: audit
      )
      event.deployments << container.deployment
      event.sftp_containers << container
    end

    def params_valid?
      errors << "Container must be a Sftp Container" unless container.is_a?(Deployment::Sftp)
      errors << "Missing audit" unless audit
      errors.empty?
    end

  end
end
