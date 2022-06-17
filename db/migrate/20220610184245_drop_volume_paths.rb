class DropVolumePaths < ActiveRecord::Migration[6.1]
  def change
    remove_column :volumes, :container_service_id, :bigint
    remove_column :volumes, :container_path, :string
  end
end
