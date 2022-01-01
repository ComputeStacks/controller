module Volumes
  module BackupVolume
    extend ActiveSupport::Concern

    def create_backup!(name)
      name = name.strip.gsub(" ","-").gsub("$","").gsub("*", "")
      return false if name.blank?
      return false if nodes.online.empty?
      update_consul! if consul_entry.nil?
      name = Zaru.sanitize!(name)
      selected_node = consul_active_node
      return false if selected_node.nil?
      init_consul_job!({
                         name: "volume.backup",
                         archive: name,
                         volume: self.name,
                         audit_id: self.current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    def delete_backup!(name)
      return false if name.blank?
      return false if nodes.online.empty?
      update_consul! if consul_entry.nil?
      selected_node = consul_active_node
      return false if selected_node.nil?
      init_consul_job!({
                         name: "backup.delete",
                         archive: name,
                         volume: self.name,
                         audit_id: self.current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    def restore_backup!(name)
      return false if name.blank?
      return false if nodes.online.empty?
      update_consul! if consul_entry.nil?
      selected_node = consul_active_node
      return false if selected_node.nil?
      init_consul_job!({
                         name: "volume.restore",
                         archive: name,
                         volume: self.name,
                         audit_id: self.current_audit&.id,
                         node: selected_node.hostname
                       })
    end

    private

    def init_consul_job!(data)
      jid = SecureRandom.uuid
      if Diplomat::Kv.put("jobs/#{jid}", data.to_json, consul_config)
        current_audit.update_attribute(:raw_data, {job_id: jid}.to_yaml) if current_audit
        true
      else
        false
      end
    end

  end
end
