module ContainerServices
  module Wordpress
    extend ActiveSupport::Concern

    def is_wordpress?
      return false unless Feature.check('wp_beta')
      container_image.role == 'wordpress' && env_params.where(name: "CS_AUTH_KEY").exists?
    end

    def wp_protected_credentials
      s = secrets.find_by(key_name: "protected_mode_pw")
      return nil if s.nil?
      {
        username: "wp",
        password: s.decrypted
      }
    end

  end
end
