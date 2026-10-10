class AddOnLatestImageToDeploymentSftps < ActiveRecord::Migration[7.2]
  # Stored by NodeServices::BastionImageStatusService (daily, via NodeWorkers::UpdateImageWorker)
  # so the bastion API never queries the node. Default true: unknown is reported as latest.
  def change
    add_column :deployment_sftps, :on_latest_image, :boolean, default: true, null: false
  end
end
