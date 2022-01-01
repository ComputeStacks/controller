module ContainerImages
  module SettingParamsHelper

    def new_container_image_setting_path(image)
      return nil if image.nil?
      "#{container_image_path(image)}/setting_params/new"
    end

    def edit_container_image_setting_path(setting)
      return "/container_images" if setting.nil?
      "#{container_image_setting_path(setting)}/edit"
    end

    def container_image_setting_path(setting)
      return "/container_images" if setting.nil?
      "#{container_image_path(setting.container_image)}/setting_params/#{setting.id}"
    end

  end
end