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
        container.global_id,
        event.global_id,
        %w(/usr/bin/ruby /usr/local/bin/load_ssh_keys.rb)
      )
    end

    private

    def build_event!
      self.event = EventLog.create!(
        locale_keys: { container: container.name },
        locale: 'sftp.reload_ssh_keys',
        status: "pending",
        event_code: "52a00936df3e2289",
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
