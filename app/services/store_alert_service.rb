class StoreAlertService
  attr_accessor :data

  # @param [Hash] data
  def initialize(data = {})
    self.data = data
  end

  def perform
    data[:alerts].each do |d|
      # Alertmanager batches alerts by group; the payload's top-level status is "firing"
      # while any alert in the group fires. Each alert carries its own status.
      status = d[:status].presence || data[:status]

      existing_alert = AlertNotification.find_by(fingerprint: d[:fingerprint])
      if existing_alert
        assign_node existing_alert, d[:labels] if existing_alert.node.nil?
        existing_alert.last_reported_at = Time.now if status == "firing"
        if status == "firing" && !existing_alert.active?
          trigger_alert = existing_alert.last_event < 10.minutes.ago # Don't trigger on alerts that were triggered less than 10 min ago.
          existing_alert.update(
            status: status,
            last_event: Time.now,
            event_count: existing_alert.event_count + 1
          )
          # Alert was previously done, so we need to notify that it's happening again.
          ProcessAlertWorker.perform_async(existing_alert.id) if trigger_alert
        else
          existing_alert.status = status
          existing_alert.save
          if existing_alert.name == "NodeUp" && existing_alert.node
            NodeWorkers::HeartbeatWorker.perform_async existing_alert.node.global_id
          end
        end
        next
      end

      next if /backup/.match?(d.dig(:labels, :name))

      # Temporarily disabling cpu usage alerts.
      if d.dig(:labels, :alertname) == "ContainerCpuUsage"
        next
      end

      alert = AlertNotification.new fingerprint: d[:fingerprint], status: status, last_event: Time.now
      alert.last_reported_at = Time.now if status == "firing"

      alert.severity = d[:labels][:severity] if d.dig(:labels, :severity)
      assign_node alert, d[:labels]
      alert.name = d[:labels][:alertname] if d.dig(:labels, :alertname)
      alert.service = d[:labels][:service] if d.dig(:labels, :service)

      if d.dig(:labels, :name)
        alert.container = find_container d[:labels][:name]
        alert.sftp_container = find_sftp_container(d[:labels][:name]) unless alert.container
        if alert.container.nil? && alert.sftp_container.nil?
          alert.labels[:container] = d[:labels][:name]
        end
      end

      if d.dig(:annotations, :description)
        alert.description = sanitize_description d[:annotations][:description]
      end

      if d.dig(:annotations, :value)
        alert.value = d[:annotations][:value].to_f.round(4)
      elsif d.dig(:annotations, :description)
        alert.value = parse_value_from_desc d[:annotations][:description]
      end

      ProcessAlertWorker.perform_async(alert.id) if alert.save
      Rails.logger.warn "[ALERT] #{d.to_json}"
    end
  end

  private

  # Sets the alert's node from its labels. When no node matches (an infra host such as
  # the controller, or a label that drifted), the raw `node` and `instance` labels are
  # kept on the alert so the admin still shows which host it is about -- but only for
  # host alerts. Container alerts (those with a `name` label) reach customers, whose
  # views and notifiers render every label.
  #
  # @param [AlertNotification] alert
  # @param [Hash] labels
  def assign_node(alert, labels)
    return if labels.blank?
    node = find_node(labels[:node], labels[:instance])
    if node
      alert.node = node
      alert.labels = alert.labels.except("node", "instance")
    elsif labels[:name].blank? && (labels[:node].present? || labels[:instance].present?)
      alert.labels = alert.labels.merge({"node" => labels[:node], "instance" => labels[:instance]}.compact_blank)
    end
  end

  # @param [String] container_name
  # @return [Deployment::Container]
  def find_container(container_name)
    Deployment::Container.find_by name: container_name
  end

  # @param [String] container_name
  # @return [Deployment::Sftp]
  def find_sftp_container(container_name)
    Deployment::Sftp.find_by name: container_name
  end

  # Match the `node` label against the node's hostname, then the address in the
  # `instance` label ("172.16.2.9:9100") against its primary IP.
  #
  # @param [String] node_name
  # @param [String] instance
  # @return [Node]
  def find_node(node_name, instance)
    node = Node.find_by("lower(hostname) = ?", node_name.to_s.strip.downcase) if node_name.present?
    return node if node
    host = instance.to_s.strip.sub(/:\d+\z/, "").delete("[]")
    # primary_ip defaults to 127.0.0.1, so a loopback scrape would match an unconfigured node.
    return nil if host.blank? || host == "localhost" || host.start_with?("127.") || host == "::1"
    Node.find_by(primary_ip: host)
  end

  # @param [String] description
  # @return [String]
  def sanitize_description(description)
    description = description.split("LABELS")[0].split("VALUE")[0].strip
    description.delete("\n")
  end

  # Find the value from the description
  # @param [String] description
  def parse_value_from_desc(description)
    val = description.split("VALUE = ")
    val[1].nil? ? nil : val[1].split("\n")[0].to_f.round(4)
  end
end
