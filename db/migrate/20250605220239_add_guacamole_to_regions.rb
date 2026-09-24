class AddGuacamoleToRegions < ActiveRecord::Migration[7.1]
  def change
    add_column :regions, :guac_url, :string
    add_column :regions, :guac_key_enc, :text
  end
end
