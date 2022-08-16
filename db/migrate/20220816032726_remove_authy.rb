class RemoveAuthy < ActiveRecord::Migration[6.1]
  def change
    remove_column :users, :authy_id, :string
    remove_column :users, :authy_enabled, :boolean
    Setting.where(category: 'authy').delete_all
  end
end
