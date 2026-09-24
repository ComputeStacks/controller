module ImageWorkers
  class AddImagePluginWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: "dep"

    def perform(current_user_id, image_id, plugin_id, cascade = false)
      user = User.find current_user_id
      image = ContainerImage.find image_id
      plugin = ContainerImagePlugin.find plugin_id

      p = ImageServices::AddImagePluginService.new image, plugin
      p.current_user = user
      p.cascade = cascade
      unless p.perform
        SystemEvent.create!(
          message: "Error adding plugin to image: #{image.name}",
          log_level: "warn",
          data: {
            plugin: plugin&.label,
            errors: p.errors
          },
          event_code: "53692783552ce8df"
        )
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
