class CreateDeploymentSftpHostKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :deployment_sftp_host_keys do |t|
      t.bigint :sftp_container_id
      t.text :pkey, null: false
      t.text :pubkey, null: false
      t.string :algo, null: false

      t.timestamps
      t.index :sftp_container_id
    end
  end
end
