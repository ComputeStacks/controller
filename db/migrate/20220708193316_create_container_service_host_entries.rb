class CreateContainerServiceHostEntries < ActiveRecord::Migration[6.1]
  def change
    create_table :container_service_host_entries do |t|
      t.bigint :container_service_id
      t.bigint :template_id
      t.string :hostname
      t.string :ipaddr
      t.boolean :keep_updated, default: true, null: false

      t.timestamps
    end
    add_index :container_service_host_entries, :container_service_id
    add_index :container_service_host_entries, :template_id
  end
end
