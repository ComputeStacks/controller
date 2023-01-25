module ImageWorkers
  class RemoveImagePluginWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'dep'

    def perform(current_user_id, image_id, plugin_id)
      user = User.find current_user_id
      image = ContainerImage.find image_id
      plugin = ContainerImagePlugin.find plugin_id

      p = ImageServices::RemoveImagePluginService.new image, plugin
      p.current_user = user
      unless p.perform
        SystemEvent.create!(
          message: "Error removing plugin from image: #{image.name}",
          log_level: "warn",
          data: {
            plugin: plugin&.label,
            errors: p.errors
          },
          event_code: "8826d365c5259ec1"
        )
      end

    rescue ActiveRecord::RecordNotFound
      return
    end

  end
end
