module LetsEncryptServices
  # Generate a DNS Challenge for LetsEncrypt
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
          data: "DnsChallenegeError #{lets_encrypt_auth.domain}: #{errors.join(', ')}",
          event_code: '4a46fa447bd82fef'
        )
        return false
      end
      zone_client = zone.state_load!
      existing_record = nil

      record_base = "#{lets_encrypt_auth.record_name}.#{lets_encrypt_auth.domain.gsub('*.','')}"

      (accepted_names ||= []) << record_base
      accepted_names << "#{record_base}."

      record_id = nil

      zone_client.records[lets_encrypt_auth.record_type].each_with_index do |i,k|
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

      if response['success']
        zone.commit_changes = true
        zone.save
      else
        self.errors << response['message'] if response['message']
      end

      event.event_details.create!(
        data: "DnsChallenegeError #{lets_encrypt_auth.domain}: #{errors.join(', ')}",
        event_code: '5ad5af9411d06754'
      ) unless errors.empty?

      errors.empty?
    end

    private

    # @return [Boolean]
    def valid?
      unless lets_encrypt_auth.challenge_type == 'dns'
        self.errors << "Invalid challenge type"
      end
      if lets_encrypt_auth.record_content.blank?
        self.errors << "Missing record_content type"
      end
      if lets_encrypt_auth.record_name.blank?
        self.errors << "Missing record name"
      end
      self.zone = lets_encrypt_auth.dns_zone
      if zone.nil?
        self.errors << "Missing Zone"
      elsif !zone.system_can_update?
        self.errors << "Unable to modify zone with pending updates"
      end
      errors.empty?
    end

  end
end
