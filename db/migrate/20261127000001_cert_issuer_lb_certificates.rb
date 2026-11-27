class CertIssuerLbCertificates < ActiveRecord::Migration[7.2]
  ALIAS_ZONE_DESCRIPTION = "Zone managed by the DNS provider (le_dns_provider) for load balancer certificate validation. Each load balancer's '_acme-challenge.<domain>' must be a CNAME to 'lb<id>.<zone>'. Leave blank only if the DNS provider manages each load balancer's domain directly.".freeze

  def up
    add_column :lets_encrypts, :next_attempt_at, :datetime
    add_column :lets_encrypts, :failure_count, :integer, default: 0, null: false

    Setting.reset_column_information
    Setting.where(name: "le_dns_sleep", category: "acme").delete_all
    # update_columns: keep updated_at so bootstrap still sees the row as untouched.
    Setting.where(name: "le_dns_alias_zone", category: "acme").find_each do |s|
      s.update_columns(description: ALIAS_ZONE_DESCRIPTION)
    end
    Setting.le_dns_provider
    Setting.le_dns_provider_secret
  end

  def down
    remove_column :lets_encrypts, :failure_count
    remove_column :lets_encrypts, :next_attempt_at
  end
end
