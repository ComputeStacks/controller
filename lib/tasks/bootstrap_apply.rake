namespace :bootstrap do
  desc "Apply a bootstrap manifest (see doc/bootstrap_manifest.md). " \
       "Usage: rake bootstrap:apply[/var/lib/computestacks/manifest.yml]. " \
       "Set DRY_RUN=1 to print the diff and write nothing. " \
       "Set UPDATE_ADDRESSES=1 to also converge the infrastructure addresses (a region's " \
       "acme_server, a node's agent_host, the DNS driver's endpoint) on rows that already " \
       "exist — for a deliberate topology change, and a full run only. " \
       "Bootstraps, does not converge: it creates what is missing and never modifies a row " \
       "that already exists — differences are reported as warnings and the database wins."
  task :apply, [:manifest] => :environment do |_t, args|
    manifest_path = args[:manifest].presence || ENV["MANIFEST"].presence

    if manifest_path.blank?
      abort "bootstrap:apply requires a manifest path — rake bootstrap:apply[/path/to/manifest.yml]"
    end

    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"]) || false
    # Off unless asked for, and asking for it is a deliberate topology change.
    # See doc/bootstrap_manifest.md, "Exemptions from bootstrap-only".
    update_addresses = ActiveModel::Type::Boolean.new.cast(ENV["UPDATE_ADDRESSES"]) || false

    begin
      Bootstrap::ApplyService.new(
        manifest_path,
        dry_run: dry_run,
        update_addresses: update_addresses
      ).perform
    rescue Bootstrap::Error => e
      # Loud and non-zero: the provisioner treats any non-zero exit as a failed
      # seed, and the message names the manifest section and key.
      warn ""
      warn "bootstrap:apply FAILED — #{e.message}"
      warn "Nothing was written; the whole apply rolled back."
      exit 1
    rescue => e
      warn ""
      warn "bootstrap:apply FAILED — #{e.class}: #{e.message}"
      warn e.backtrace.first(15).join("\n") if ENV["VERBOSE"].present?
      warn "Nothing was written; the whole apply rolled back."
      exit 1
    end
  end
end
