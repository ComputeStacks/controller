class AddPwAuthToDeploymentSftps < ActiveRecord::Migration[6.1]
  def change
    add_column :deployment_sftps, :pw_auth, :boolean, default: true, null: false
    add_column :users, :c_sftp_pass, :boolean, default: true, null: false
  end
end
