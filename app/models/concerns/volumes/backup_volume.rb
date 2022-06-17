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
                         volume: self.name,
                         source_volume: self.name,
                         audit_id: self.current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    def restore_backup!(snapshot_name, source_volume_name = nil)
      return false if snapshot_name.blank?
      return false if nodes.online.empty?
      update_consul! if consul_entry.nil?
      selected_node = consul_active_node
      return false if selected_node.nil?
      init_consul_job!({
                         name: "volume.restore",
                         archive: snapshot_name,
                         volume: self.name,
                         source_volume: source_volume_name.nil? ? self.name : source_volume_name,
                         audit_id: self.current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    private

    def init_consul_job!(data)
      jid = SecureRandom.uuid
      if Diplomat::Kv.put("jobs/#{jid}", data.to_json, consul_config)
        if current_audit
          current_audit.update raw_data: { job_id: jid }.to_yaml
        end
        true
      else
        false
      end
    end

  end
end
