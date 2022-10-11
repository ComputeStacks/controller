module ContainerServiceWorkers
  class VariantMigrationWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(service_id, audit_id, old_variant_id)
      service = Deployment::ContainerService.find service_id
      audit = Audit.find audit_id
      old_variant = ContainerImage::ImageVariant.find old_variant_id

      return unless service && audit && old_variant

      ContainerServices::VariantMigrationService.new(service, audit, old_variant).perform

    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue => e
      user = audit.user if defined?(audit) && audit.user
      ExceptionAlertService.new(e, '81deb075007334ac', user).perform
    end

  end
end
