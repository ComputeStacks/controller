module ContainerImages
  module SettingParamsHelper

    # @param [ContainerImage] image
    def container_image_settings_path(image)
      return container_images_path if image.nil?
      "#{container_image_path(image)}/setting_params"
    end

    # @param [ContainerImage::SettingParam] setting
    def container_image_setting_path(setting)
      return container_images_path if setting.nil?
      "#{container_image_settings_path(setting.container_image)}/#{setting.id}"
    end

    # @param [ContainerImage] image
    def new_container_image_setting_path(image)
      return nil if image.nil?
      "#{container_image_settings_path(image)}/new"
    end

    # @param [ContainerImage::SettingParam] setting
    def edit_container_image_setting_path(setting)
      return container_images_path if setting.nil?
      "#{container_image_setting_path(setting)}/edit"
    end

  end
end
