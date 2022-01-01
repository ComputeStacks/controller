class AddMetadataToDeployments < ActiveRecord::Migration[6.1]
  def change
    add_column :deployments, :consul_policy_id, :string
    add_column :deployments, :consul_auth_id, :string
    add_column :deployments, :consul_auth_key, :string
    add_column :regions, :consul_token, :string
  end
end
