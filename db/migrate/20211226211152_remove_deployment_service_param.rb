class RemoveDeploymentServiceParam < ActiveRecord::Migration[6.1]
  def change
    drop_table :deployment_container_service_params
  end
end
