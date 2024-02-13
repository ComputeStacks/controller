module Volumes
  module BackupVolume
    extend ActiveSupport::Concern

    def create_backup!(snapshot_name)
      snapshot_name = snapshot_name.strip.gsub(" ","-").gsub("$","").gsub("*", "")
      return false if name.blank?
      return false if nodes.online.empty?

      update_consul! if consul_entry.nil?
      snapshot_name = Zaru.sanitize!(snapshot_name)
      selected_node = consul_active_node
      return false if selected_node.nil?

      init_consul_job!({
                         name: "volume.backup",
                         archive: snapshot_name,
                         volume: self.name,
                         source_volume: self.name,
                         audit_id: self.current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    def delete_backup!(snapshot_name)
      return false if snapshot_name.blank?
      return false if nodes.online.empty?

      update_consul! if consul_entry.nil?
      selected_node = consul_active_node
      return false if selected_node.nil?

      init_consul_job!({
                         name: "backup.delete",
                         archive: snapshot_name,
                         volume: name,
                         source_volume: name,
                         audit_id: current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    def restore_backup!(snapshot_name, source_volume_name = nil)
      if snapshot_name.blank?
        if current_audit&.event_logs&.exists?
          current_audit.event_logs.first.event_details.create!(
            data: "[Snapshot Restore] Error: Missing snapshot name.",
            event_code: "8715836b24c7898c"
          )
        end
        return false
      end
      if nodes.online.empty?
        if current_audit&.event_logs&.exists?
          current_audit.event_logs.first.event_details.create!(
            data: "[Snapshot Restore] Error: No online nodes found. | Total nodes: #{nodes.count} | Online nodes: #{nodes.online.count}",
            event_code: "e747dac60227ea25"
          )
        end
        return false
      end
      update_consul! if consul_entry.nil?
      selected_node = consul_active_node
      if selected_node.nil?
        if current_audit&.event_logs&.exists?
          current_audit.event_logs.first.event_details.create!(
            data: "[Snapshot Restore] Error: Missing active node\n\n#{consul_entry.inspect}",
            event_code: "7b8fb2202547cc81"
          )
        end
        return false
      end
      init_consul_job!({
                         name: "volume.restore",
                         archive: snapshot_name,
                         volume: name,
                         source_volume: source_volume_name.nil? ? name : source_volume_name,
                         audit_id: current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    private

    def init_consul_job!(data)
      jid = SecureRandom.uuid
      if Diplomat::Kv.put("jobs/#{jid}", data.to_json, consul_config)
        current_audit&.update raw_data: { job_id: jid }.to_yaml
        true
      else
        false
      end
    end

  end
end
