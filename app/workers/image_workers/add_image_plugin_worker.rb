module ImageWorkers
  class AddImagePluginWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'dep_critical'

    def perform(image_id, plugin_id, cascade = false)
      image = ContainerImage.find image_id
      plugin = ContainerImagePlugin.find plugin_id

      p = ImageServices::AddImagePluginService.new image, plugin
      p.cascade = cascade
      unless p.perform
        # capture errors
      end

    rescue ActiveRecord::RecordNotFound
      return
    end

  end
end
