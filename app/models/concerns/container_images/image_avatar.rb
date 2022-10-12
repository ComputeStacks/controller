module ContainerImages
  module ImageAvatar
    extend ActiveSupport::Concern

    class_methods do

      def default_avatar_path
        "icons/stacks/docker.png"
      end

    end

    def icon_url
      file_icon_name = name.split("_").first.split('-').first.strip.downcase
      file_icon_name = "elasticsearch" if role == "elasticsearch" || name == "elastic"
      file_icon_name = "redis" if role == "redis"
      file_icon_name = "ghost" if role == "ghost"
      file_icon_name = "joomla" if role == "joomla"
      file_icon_name = "nextcloud" if role == "nextcloud"
      icon_path = "icons/stacks/#{file_icon_name}.png"
      icon_exists?(icon_path) ? icon_path : ContainerImage.default_avatar_path
    end

  end
end
