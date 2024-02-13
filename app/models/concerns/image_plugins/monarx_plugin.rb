module ImagePlugins
  module MonarxPlugin
    extend ActiveSupport::Concern

    included do
      scope :monarx, -> { where name: 'monarx' }
    end

    def monarx_base_url
      "https://api.monarx.com/v1"
    end

    def monarx_enterprise_url
      monarx_base_url + "/enterprise/#{Setting.monarx_enterprise_id}"
    end

    def monarx_api_headers
      {
        "accept" =>  "application/json",
        "x-api-id" => Setting.monarx_api_key,
        "x-api-key" => Setting.monarx_api_secret
      }
    end

    # @return [Boolean]
    def monarx_available?
      return false unless Setting.monarx_enabled?
      return false if Setting.monarx_api_key.blank?
      return false if Setting.monarx_api_secret.blank?
      return false if Setting.monarx_agent_key.blank?
      return false if Setting.monarx_agent_secret.blank?
      return false if Setting.monarx_enterprise_id.blank?

      true
    end

    # Only admins can enable/disable monarx (since it's paid)
    def monarx_can_enable?(user)
      user.is_admin
    end

  end
end
