class StoreAlertService

  attr_accessor :data

  # @param [Hash] data
  def initialize(data = {})
    self.data = data
  end

  def perform
    data[:alerts].each do |d|
      existing_alert = AlertNotification.find_by(fingerprint: d[:fingerprint])
      if existing_alert
        if data[:status] == 'firing' && !existing_alert.active?
          trigger_alert = existing_alert.last_event < 10.minutes.ago # Don't trigger on alerts that were triggered less than 10 min ago.
          existing_alert.update(
            status: data[:status],
            last_event: Time.now,
            event_count: existing_alert.event_count + 1
          )
          # Alert was previously done, so we need to notify that it's happening again.
          ProcessAlertWorker.perform_async(existing_alert.id) if trigger_alert
        else
          existing_alert.update_attribute :status, data[:status]
          if existing_alert.name == 'NodeUp' && existing_alert.node
            NodeWorkers::HeartbeatWorker.perform_async existing_alert.node.global_id
          end
        end
        next
      end

      next if d.dig(:labels, :name) =~ /backup/

      alert = AlertNotification.new fingerprint: d[:fingerprint], status: data[:status], last_event: Time.now

      alert.severity = d[:labels][:severity] if d.dig(:labels, :severity)
      alert.node = find_node(d[:labels][:node]) if d.dig(:labels, :node)
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

  # @param [String] node_name
  # @return [Node]
  def find_node(node_name)
    Node.find_by hostname: node_name
  end

  # @param [String] description
  # @return [String]
  def sanitize_description(description)
    description = description.split("LABELS")[0].split("VALUE")[0].strip
    description.gsub("\n","")
  end

  # Find the value from the description
  # @param [String] description
  def parse_value_from_desc(description)
    val = description.split("VALUE = ")
    val[1].nil? ? nil : val[1].split("\n")[0].to_f.round(4)
  end


end
