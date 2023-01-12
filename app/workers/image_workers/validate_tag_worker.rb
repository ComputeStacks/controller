module ImageWorkers
  class ValidateTagWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: 'default'

    def perform(image_or_variant_id)
      obj = GlobalID::Locator.locate image_or_variant_id
      return false if obj.nil?

      case obj
      when ContainerImage
        obj.image_variants.each do |i|
          i.skip_tag_validation = true
          i.validated_tag = i.registry_image_available?
          i.validated_tag_updated = Time.now
          i.save
        end
      when ContainerImage::ImageVariant
        obj.skip_tag_validation = true
        obj.validated_tag = obj.registry_image_available?
        obj.validated_tag_updated = Time.now
        obj.save
      end
    rescue ActiveRecord::RecordNotFound
      return
    end

  end
end
