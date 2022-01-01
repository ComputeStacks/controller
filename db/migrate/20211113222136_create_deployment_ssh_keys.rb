class CreateDeploymentSshKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :deployment_ssh_keys do |t|
      t.bigint :deployment_id
      t.string :label
      t.text :pubkey, null: false

      t.timestamps
      t.index :deployment_id
    end
  end
end
