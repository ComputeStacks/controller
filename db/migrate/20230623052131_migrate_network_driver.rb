class MigrateNetworkDriver < ActiveRecord::Migration[7.0]
  def change

    # Ensure existing calido networks are updated correctly.
    Region.all.each do |region|
      if region.has_clustered_networking?
        region.networks.each do |net|
          net.update_column :network_driver, 'calico_docker'
        end
      end
    end

  end
end
