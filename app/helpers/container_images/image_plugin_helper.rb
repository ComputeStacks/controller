module ContainerImages
  module ImagePluginHelper

    # @param [ContainerImage] image
    def new_container_image_plugin_path(image)
      return nil if image.nil?
      "#{container_image_path(image)}/image_plugins/new"
    end

    # @param [ContainerImage] image
    # @param [ContainerImagePlugin] plugin
    def container_image_plugin_path(image, plugin)
      return "/container_images" if plugin.nil? || image.nil?
      "#{container_image_path(image)}/image_plugins/#{plugin.id}"
    end

  end
end
