namespace :dns do
  desc "One-time, after the pdns 1.2.0 upgrade: re-dump every pending DNS edit (dns_zones.saved_state) without its API client, so decrypted provider credentials no longer sit in the column. Keeps the pending edits and their timestamps. Makes no provider calls. Idempotent — safe to re-run. Exits non-zero if any row failed."
  task scrub_saved_state: :environment do
    scrubbed = 0
    failed = 0
    Dns::Zone.where.not(saved_state: nil).find_each do |zone|
      dump = Dns::Zone.dump_state(Marshal.load(zone.saved_state))
      if dump == zone.saved_state
        puts "[ok] zone #{zone.id} (#{zone.name}): already clean"
      else
        zone.update_columns(saved_state: dump)
        scrubbed += 1
        puts "[scrubbed] zone #{zone.id} (#{zone.name})"
      end
    rescue => e
      failed += 1
      puts "[error] zone #{zone.id} (#{zone.name}): #{e.class}: #{e.message}"
    end
    puts "\nScrubbed #{scrubbed}, failed #{failed}."
    exit 1 if failed > 0
  end
end
