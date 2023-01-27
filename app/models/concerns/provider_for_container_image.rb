##
# Manage image authorizations
module ProviderForContainerImage
  extend ActiveSupport::Concern

  included do

    belongs_to :container_image_provider, optional: true
    has_one :container_registry, through: :container_image_provider

    before_validation :cleanup_registry_custom

  end

  def image_auth
    return nil if container_image_provider.nil? && registry_custom.blank? # Shouldn't happen.
    return nil if container_registry.nil? && !registry_auth
    if container_registry
      {
        'username' => registry_username,
        'password' => container_registry.registry_password
      }
    else
      reg_client = registry_client
      if reg_client.token_endpoint
        {
          'username' => registry_username,
          'password' => registry_password,
          'serveraddress' => reg_client.token_endpoint
        }
      else
        {
          'username' => registry_username,
          'password' => registry_password
        }
      end
    end
  end

  def registry_password
    return nil if registry_password_encrypted.blank?
    Secret.decrypt!(registry_password_encrypted)
  end

  def registry_password=(pw)
    self.registry_password_encrypted = Secret.encrypt!(pw)
  end

  def provider_path
    container_image_provider.nil? ? registry_custom : container_image_provider.hostname
  end

  def registry_client
    if provider_path.blank? || container_image_provider&.name == 'DockerHub'
      reg_uri = [nil]
      port = 443
      auth_hash = if registry_password.blank?
                    {}
                  else
                    {
                      username: registry_username,
                      password: registry_password
                    }
                  end
    else
      reg_uri = provider_path.strip.split(':')
      port = reg_uri.count == 1 ? 443 : reg_uri.last.split('/').first.to_i
      auth_hash = {
        username: registry_username,
        password: container_registry ? container_registry.registry_password : registry_password
      }
    end
    DockerRegistry::Client.new(reg_uri.first, port, auth_hash)
  end

  def registry_image_client
    p = if (provider_path.blank? || container_image_provider&.name == 'DockerHub') && registry_image_path.split('/').count == 1
      "library/#{registry_image_path}"
    else
      registry_image_path
    end
    DockerRegistry::Image.new(registry_client, p)
  end

  def cleanup_registry_custom
    unless registry_custom.blank?
      self.registry_custom = registry_custom.gsub("http://",'').gsub("https://",'').split('/').first.strip
    end
  end

end
