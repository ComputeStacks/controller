module ContainerServiceWorkers
  class VariantMigrationWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    # @param [Hash] callback_params {authorization: String, url: String}
    def perform(service_id, audit_id, old_variant_id, callback_params = {})
      service = Deployment::ContainerService.find service_id
      audit = Audit.find audit_id
      old_variant = ContainerImage::ImageVariant.find old_variant_id

      return unless service && audit && old_variant

      variant_migration = ContainerServices::VariantMigrationService.new(service, audit, old_variant)

      unless callback_params.nil? || callback_params.empty? 
        variant_migration.build_event! callback_params
      end

      variant_migration.perform

    rescue ActiveRecord::RecordNotFound
      nil # Silently fail
    rescue => e
      user = audit.user if defined?(audit) && audit.user
      ExceptionAlertService.new(e, "81deb075007334ac", user).perform
    end
  end
end
