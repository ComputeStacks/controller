module ContainerServices
  # Given a service, run any variant scripts and rebuild the container
  class VariantMigrationService

    attr_accessor :container,
                  :previous_variant,
                  :service,
                  :audit,
                  :event

    # @param [Deployment::ContainerService] service
    # @param [Audit] audit
    # @param [ContainerImage::ImageVariant] old_variant
    def initialize(service, audit, old_variant)
      self.service = service
      self.previous_variant = old_variant
      self.container = nil # The container we'll use to perform this action on
      self.audit = audit
      self.event = nil
    end

    # @return [Boolean]
    def perform
      build_event!
      return false unless valid?
      service.containers.each do |i|
        self.container = i if i.running?(true)
        break if container
      end unless container
      # IF we don't need to run any scripts, allow stopped containers.
      self.container = service.containers.first if container.nil? && allow_stopped?
      return false unless can_perform?
      return false unless pre_migration!
      return false unless rebuild!
      return false unless post_migration!
      true
    rescue => e
      ExceptionAlertService.new(e, '3932bc1fa2eebfcf').perform
      if defined?(event)
        event.event_details.create!(
          data: "Fatal error: #{e.message}",
          event_code: "3932bc1fa2eebfcf"
        )
        event.fail! "Fatal Error"
      end
      false
    ensure
      if event
        self.event.reload
        event.done! if event.running?
      end
    end

    def allow_stopped?
      v = service.image_variant
      v.before_migrate.blank? && v.after_migrate.blank? && v.rollback_migrate.blank?
    end

    private

    def pre_migration!
      Timeout::timeout(300) do
        # Exec pre migrate script
        before_migrate = service.variant_pre_script container
        unless before_migrate.blank?
          if container && !Rails.env.test?
            result = container.container_exec! before_migrate, nil, 180
            event.event_details.create!(
              data: result[:response].split('\n').join("\n"),
              event_code: "30635f08f9c2ade0"
            ) unless result[:response].blank?
            if result[:exit_code] > 0
              rollback!
              return false
            end
          end
        end
        true
      end
    rescue Timeout::Error
      event.event_details.create!(
        data: "Timeout during pre migration",
        event_code: "e5250991f67c7a2b"
      ) if event
      rollback!
      false
    rescue => e
      ExceptionAlertService.new(e, '34b2ec44f520960f').perform
      event.event_details.create!(
        data: "Fatal error during pre_migration: #{e.message}",
        event_code: "34b2ec44f520960f"
      ) if event
      rollback!
      false
    end

    def rebuild!(fail_to_rollback = true)
      # When arriving from rollback, we need to refresh the image.
      unless fail_to_rollback
        self.service.reload
        self.container.reload
      end

      # Ensure image exists on node
      return false unless ProvisionServices::ImageReadyService.new(container, event).perform

      Timeout::timeout(300) do
        # Rebuild
        unless container.stop!(event, true)
          event.event_details.create!(
            data: "Failed to stop container. All recovery attempts have been halted; manual intervention required.",
            event_code: "2e2c4acc87f49bc6"
          )
          event.fail! "Fatal Error"
          return false
        end

        container.delete_from_node! event

        # Provision Container
        unless container.build!(event)
          event.event_details.create!(
            data: "Failed to build container.",
            event_code: "7233cbc5ca464e5c"
          )
          rollback!(true) if fail_to_rollback
          return false
        end

        unless container.start!(event)
          event.event_details.create!(
            data: "Failed to start container.",
            event_code: "a4f915f264b768a1"
          )
          rollback!(true) if fail_to_rollback
          return false
        end

        true
      end
    rescue Timeout::Error
      event.event_details.create!(
        data: "Timeout during  #{fail_to_rollback ? 'rebuild' : 'rollback rebuild'}",
        event_code: "772b174cb14a42b0"
      ) if event
      rollback!(true) if fail_to_rollback
      false
    rescue => e
      ExceptionAlertService.new(e, '1029d4189fed296e').perform
      event.event_details.create!(
        data: "Fatal error during #{fail_to_rollback ? 'rebuild' : 'rollback rebuild'}: #{e.message}\n\n",
        event_code: "1029d4189fed296e"
      ) if event
      rollback! if fail_to_rollback
      false
    end

    def post_migration!
      Timeout::timeout(300) do
        # Exec pre migrate script
        after_migrate = service.variant_post_script container
        unless after_migrate.blank?
          if container && !Rails.env.test?
            result = container.container_exec! after_migrate, nil, 180
            event.event_details.create!(
              data: result[:response].split('\n').join("\n"),
              event_code: "2c095a61c526be4f"
            ) unless result[:response].blank?
            if result[:exit_code] > 0
              rollback! true
              return false
            end
          end
        end
        true
      end
    rescue Timeout::Error
      event.event_details.create!(
        data: "Timeout during post migration",
        event_code: "9db27ce73abc5016"
      ) if event
      rollback! true
      false
    rescue => e
      ExceptionAlertService.new(e, 'a5f95dbea503a741').perform
      event.event_details.create!(
        data: "Fatal error during post_migration: #{e.message}",
        event_code: "a5f95dbea503a741"
      ) if event
      rollback! true
      false
    end

    # Sanity checks without rollback
    # @return [Boolean]
    def valid?
      if previous_variant.nil?
        event.event_details.create!(
          data: "Missing previous variant",
          event_code: "4271314d628ed0dd"
        )
        event.fail! "error"
        return false
      end
      if service.nil?
        event.event_details.create!(
          data: "Missing container service",
          event_code: "66df8899b7bfc852"
        )
        event.fail! "error"
        return false
      end
      true
    end

    # @return [Boolean]
    def can_perform?
      if container.nil?
        event.event_details.create!(
          data: "Unable to locate running container, aborting.",
          event_code: '5c2183886cefdf90'
        )
        event.fail! 'No online containers'
        rollback!
        return false
      end
      true
    end

    def rollback!(container_rollback = false)
      service.update current_audit: audit,
                     skip_variant_migration: true,
                     image_variant: previous_variant

      self.service.reload

      return true unless container_rollback

      rollback_success = rebuild! false

      unless rollback_success
        return false
      end

      Timeout::timeout(300) do
        # Exec rollback script
        rollback_script = service.variant_rollback_script container
        unless rollback_script.blank?
          if container && !Rails.env.test?
            container.container_exec! rollback_script, event
          end
        end
      end
    rescue Timeout::Error
      event.event_details.create!(
        data: "Timeout during rollback",
        event_code: "1e576b37618a2f85"
      ) if event
      false
    ensure
      if event
        self.event.reload
        event.fail!("Fatal error") if event.running?
      end
    end

    def build_event!
      self.event = EventLog.create!(
        locale: 'service.variant_migrate',
        locale_keys: {
          'old' => previous_variant.registry_image_tag,
          'variant' => service.image_variant.registry_image_tag,
          'image' => service.container_image.label
        },
        event_code: '0793974d766b33fe',
        status: 'running',
        audit: audit
      )
      event.deployments << service.deployment
      event.container_services << service
    end

  end

end
