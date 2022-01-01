class RemoveLicense < ActiveRecord::Migration[6.1]
  def change
    Setting.where("name = 'license' OR name = 'license_key'").delete_all
  end
end
