class LeDnsAliasZone < ActiveRecord::Migration[7.2]
  # Create the setting row so it shows under ACME settings on existing installs.
  def up
    Setting.le_dns_alias_zone
  end

  def down
  end
end
