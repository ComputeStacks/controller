module ContainerServices
  module Wordpress
    extend ActiveSupport::Concern

    def is_wordpress?
      container_image.role == 'wordpress'
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
