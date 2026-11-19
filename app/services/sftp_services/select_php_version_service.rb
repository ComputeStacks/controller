module SftpServices
  # Re-run the bastion's boot-time PHP selection after the project's metadata changes.
  class SelectPhpVersionService
    attr_accessor :container,
      :audit,
      :event,
      :errors

    def initialize(container, audit)
      self.container = container
      self.audit = audit
      self.errors = []
      self.event = nil
    end

    def perform
      return false unless params_valid?
      build_event!
      ContainerWorkers::ContainerExecWorker.perform_async(
        container.global_id,
        event.global_id,
        %w[/usr/bin/ruby /usr/local/bin/select_php_version]
      )
    rescue => e
      return false unless defined?(event) && event
      event.event_details.create!(
        event_code: "b6e1d0c4a7f35e92",
        data: e.message
      )
      event.fail! "Fatal Error"
      false
    end

    private

    def build_event!
      self.event = EventLog.create!(
        locale_keys: {container: container.name},
        locale: "sftp.select_php_version",
        status: "pending",
        event_code: "4c8f2e7a19d06b53",
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
