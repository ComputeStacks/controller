class UpdateConsulAuth < ActiveRecord::Migration[7.0]
  # No-op. This was a one-time Consul ACL-policy data migration. Consul was retired in the
  # v3.0.0 cs-agent cutover (the Diplomat gem and Region#consul_config were removed), so the
  # original body no longer resolves. It has already run on every existing database, and fresh
  # environments load db/schema.rb rather than replaying migrations — the body is neutralized
  # only to keep a from-empty `rails db:migrate` from raising NameError.
  def change
  end
end
