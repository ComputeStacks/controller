module ContainerImages
  # Validate Registry
  # In use by ContainerImage::ImageVariant
  module ImageRegistryValidator
    extend ActiveSupport::Concern

    included do
      attr_accessor :skip_tag_validation
      after_commit :update_tag_validation!, unless: proc { skip_tag_validation }
    end

    def registry_image_available?
      container_image.registry_image_client.tag_available?(registry_image_tag)
    rescue => e
      ExceptionAlertService.new(e, '4aff131c93ac3aaf').perform
      false
    end

    private

    def update_tag_validation!
      ImageWorkers::ValidateTagWorker.perform_async global_id
    end

  end
end
