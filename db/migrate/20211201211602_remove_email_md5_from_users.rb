class RemoveEmailMd5FromUsers < ActiveRecord::Migration[6.1]
  def change
    remove_column :users, :email_md5
  end
end
