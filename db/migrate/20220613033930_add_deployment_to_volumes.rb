class AddDeploymentToVolumes < ActiveRecord::Migration[6.1]
  def change

    add_column :volumes, :deployment_id, :bigint
    add_index :volumes, :deployment_id

  end
end
