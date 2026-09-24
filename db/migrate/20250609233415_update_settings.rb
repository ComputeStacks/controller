class UpdateSettings < ActiveRecord::Migration[7.1]
  def change
    Setting.where(category: "lets_encrypt").update_all category: "acme"
    Setting.setup!

    Setting.find_by(name: "le")&.update description: "Enable or Disable ACME certificates"
    Setting.find_by(name: "le_auto")&.update description: "Enable ACME scheduled job"

    Setting.find_by(name: "le_domains_per_account")&.delete
    Setting.find_by(name: "le_single_domain")&.delete

    # For existing sites, lets not break anything.
    Setting.find_by(name: "acme_email", value: "noreply@example.acme")&.update value: "acme-noreply@computestacks.com"
  end
end
