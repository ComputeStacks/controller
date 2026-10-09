class UpdateStockBastionImage < ActiveRecord::Migration[7.2]
  # The v2 bastion image reads the legacy metadata path the v9.6 cutover removed, so
  # every SFTP container built from it crash-loops. Move installs still on the stock
  # default to v4; a value the operator changed is left alone.
  OLD_IMAGE = "ghcr.io/computestacks/cs-docker-bastion:v2"
  NEW_IMAGE = "ghcr.io/computestacks/cs-docker-bastion:v4"

  def up
    execute <<~SQL
      UPDATE settings
      SET value = #{quote(NEW_IMAGE)}, updated_at = NOW()
      WHERE name = 'cs_bastion_image'
        AND category = 'computestacks'
        AND value = #{quote(OLD_IMAGE)}
    SQL
  end

  # Not reverted: v2 cannot run against this controller's metadata service.
  def down
  end
end
