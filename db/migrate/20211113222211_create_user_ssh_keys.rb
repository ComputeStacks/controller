class CreateUserSshKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :user_ssh_keys do |t|
      t.bigint :user_id
      t.string :label
      t.text :pubkey, null: false

      t.timestamps
      t.index :user_id
    end
  end
end
