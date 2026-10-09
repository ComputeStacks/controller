module LetsEncryptServices
  # Generate a DNS Challenge for LetsEncrypt
  #
  # The read-modify-write-push of the zone runs under a row lock on the zone
  # (`with_lock`), and the push to the DNS provider (`state_commit!`) happens
  # inside that lock. Several workers can write the same zone at once (every
  # load balancer shares the ACME DNS alias zone), and a provider that updates
  # by zone replaces the whole zone on push, so an unserialized writer could
  # drop another's challenge record, or trip over its uncommitted draft.
  #
  # Do not switch this to `commit_changes = true; save`: `apply_commitments`
  # runs in `after_update_commit`, i.e. after the outermost transaction (and so
  # the lock) has been released.
  #
  # @!attribute event
  #   @return [EventLog]
  # @!attribute lets_encrypt_auth
  #   @return [LetsEncryptAuth]
  # @!attribute zone
  #   @return [Dns::Zone]
  # @!attribute errors
  #   @return [Array]
  class DnsChallengeService
    attr_accessor :event,
      :lets_encrypt_auth,
      :zone,
      :errors

    # @param lets_encrypt_auth [LetsEncryptAuth]
    # @param event [EventLog]
    def initialize(lets_encrypt_auth, event)
      self.lets_encrypt_auth = lets_encrypt_auth
      self.event = event
      self.zone = nil
      self.errors = []
    end

    # @return [Boolean]
    def perform
      unless valid?
        event.event_details.create!(
          data: "DnsChallenegeError #{error_subject}: #{errors.join(", ")}",
          event_code: "4a46fa447bd82fef"
        )
        return false
      end

      # Reloads `zone` in place with `SELECT ... FOR UPDATE`.
      zone.with_lock do
        write_record!
      end

      unless errors.empty?
        event.event_details.create!(
          data: "DnsChallenegeError #{error_subject}: #{errors.join(", ")}",
          event_code: "5ad5af9411d06754"
        )
      end

      errors.empty?
    end

    private

    # Runs while holding the zone's row lock.
    def write_record!
      # Authoritative check: another writer may have left a draft since `valid?`.
      unless zone.system_can_update?
        errors << "Unable to modify zone with pending updates"
        return
      end

      by_zone = zone.available_actions.include?("update_by_zone")
      zone_client = zone.state_load!
      existing_record = nil
      record_id = nil

      record_base = lets_encrypt_auth.dns_record_fqdn
      accepted_names = [record_base, "#{record_base}."]

      zone_client.records[lets_encrypt_auth.record_type].each_with_index do |i, k|
        if accepted_names.include?(i.name) || accepted_names.include?("#{i.name}.#{zone.name}")
          existing_record = i
          record_id = k
          break
        end
      end

      zone_params = {
        ttl: 300,
        name: existing_record ? existing_record.name : "#{record_base}.",
        value: lets_encrypt_auth.record_content,
        type: lets_encrypt_auth.record_type
      }

      record = Dns::ZoneRecord.new(record_id, zone, lets_encrypt_auth.record_type)
      response = existing_record ? record.update!(zone_params) : record.create!(zone_params)

      unless response["success"]
        # The zone was clean when we took the lock, so anything in it now is ours.
        zone.state_revert! if by_zone
        errors << (response["message"].presence || "Unable to save DNS record")
        return
      end

      # Providers that do not update by zone have already saved the record.
      return unless by_zone

      result = zone.state_commit!
      unless result["success"]
        zone.state_revert!
        errors << (result["message"].presence || "Unable to update DNS zone")
      end
    end

    # @return [String]
    def error_subject
      dns_alias = lets_encrypt_auth.dns_alias
      dns_alias.present? ? "#{lets_encrypt_auth.domain} (via DNS alias #{dns_alias})" : lets_encrypt_auth.domain
    end

    # @return [Boolean]
    def valid?
      unless lets_encrypt_auth.challenge_type == "dns"
        errors << "Invalid challenge type"
      end
      if lets_encrypt_auth.record_content.blank?
        errors << "Missing record_content type"
      end
      if lets_encrypt_auth.record_name.blank?
        errors << "Missing record name"
      end
      self.zone = lets_encrypt_auth.dns_zone
      if zone.nil?
        dns_alias = lets_encrypt_auth.dns_alias
        errors << (dns_alias.present? ? "Missing DNS alias zone #{Setting.le_dns_alias_zone}" : "Missing Zone")
      elsif !zone.system_can_update?
        errors << "Unable to modify zone with pending updates"
      end
      errors.empty?
    end
  end
end
