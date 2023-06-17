class AddNetworkDriverToNetworks < ActiveRecord::Migration[7.0]
  def change
    add_column :networks, :network_driver, :string, default: 'bridge', null: false
    add_index :networks, :network_driver
  end
end
