module ContainerServices
  module ServiceVariant
    extend ActiveSupport::Concern

    included do
      after_update_commit :migrate_to_variant
      attr_accessor :skip_variant_migration
    end

    def variant_pre_script(c = nil)
      variant_parsed_command image_variant.before_migrate, c
    end

    def variant_post_script(c = nil)
      variant_parsed_command image_variant.after_migrate, c
    end

    def variant_rollback_script(c = nil)
      variant_parsed_command image_variant.rollback_migrate, c
    end

    private

    def variant_parsed_command(cmd, c)
      return "" if cmd.nil?
      cmd = cmd.strip
      return "" if cmd.blank?
      c = containers.first if c.nil?
      return "" if c.nil?
      data = Liquid::Template.parse cmd
      vars = { 'service_name_short' => c.var_lookup('build.self.service_name_short') }
      setting_params.each do |param|
        vars[param.name] = c.var_lookup("build.settings.#{param.name}")
      end
      rsp = data.render(vars).split(" ")
      Rails.logger.warn "[FOO] #{rsp}"
      rsp
    end

    # Migrate service to new image variant
    def migrate_to_variant
      Rails.logger.warn "[FOO] 1"
      return if skip_variant_migration
      Rails.logger.warn "[FOO] 2"
      return unless image_variant_id_previously_changed?
      Rails.logger.warn "[FOO] 3"
      return if current_audit.nil?
      prev_variant = image_variant_id_previously_was
      Rails.logger.warn "[FOO] 4 | #{image_variant_id_previously_was}"
      return unless prev_variant
      Rails.logger.warn "[FOO] 5 | #{image_variant_id}"
      ContainerServiceWorkers::VariantMigrationWorker.perform_async id, current_audit.id, prev_variant
    end

  end
end
