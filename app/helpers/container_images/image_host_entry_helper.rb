module ContainerImages
  module ImageHostEntryHelper

    # @param [ContainerImage] image
    def new_container_image_host_entry_path(image)
      return nil if image.nil?
      "#{container_image_path(image)}/custom_host_entries/new"
    end

    # @param [ContainerImage::CustomHostEntry] entry
    def container_image_host_entry_path(entry)
      return "/container_images" if entry.nil?
      "#{container_image_path(entry.container_image)}/custom_host_entries/#{entry.id}"
    end

    # @param [ContainerImage::CustomHostEntry] entry
    def edit_container_image_host_entry_path(entry)
      return "/container_images" if entry.nil?
      "#{container_image_host_entry_path(entry)}/edit"
    end

  end
end
