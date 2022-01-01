module ImageWorkers
  class ValidateTagWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: 'default'

    def perform(image_id)
      image = ContainerImage.find_by(id: image_id)
      return false if image.nil?

      image.skip_tag_validation = true
      image.validated_tag = image.registry_image_available?
      image.validated_tag_updated = Time.now
      image.save
    end

  end
end
