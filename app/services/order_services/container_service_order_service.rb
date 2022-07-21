module OrderServices
  class ContainerServiceOrderService

    attr_accessor :order,
                  :event,
                  :project,
                  :product, # In the `data` loop, these are the params
                  :result,
                  :provision_state, # Track what the parent hash
                  :errors

    def initialize(order, event, project, product)
      self.order = order
      self.event = event
      self.project = project
      self.product = product
      self.errors = []
      self.result = {
        containers: [],
        subscriptions: [],
        load_balancers: [],
        volumes: [],
        volume_map: [] # [ { template: csrn, volume: csrn } ]
      }

      # The result hash that's getting added to each cycle.
      self.provision_state = {
        containers: [],
        subscriptions: [],
        load_balancers: [],
        volumes: [],
        volume_map: [] # [ { template: csrn, volume: csrn } ]
      }
    end

    def perform
      return false unless valid?
      product_id = if product.dig(:product, :id)
                     product.dig(:product, :id) # deprecated
                   elsif product.dig(:resources, :product_id)
                     product.dig(:resources, :product_id)
                   elsif product.dig(:resources, :package_id) # deprecated
                     product.dig(:resources, :package_id) # package_id is actually product_id!
                   else
                     nil
                   end
      job = ProvisionServices::ContainerServiceProvisioner.new(
        order.user,
        project,
        event,
        {
          qty: product[:qty].to_i.zero? ? 1 : product[:qty].to_i,
          label: product[:label],
          region_id: order.data[:region_id],
          image_id: product[:container_id],
          product_id: product_id,
          cpu: product.dig(:resources, :cpu).to_f,
          memory: product.dig(:resources, :memory).to_i,
          settings: product[:params],
          volume_config: product[:volume_config].nil? ? [] : product[:volume_config],
          external_id: product[:remote_service_id]
        }
      )
      job.provision_state = provision_state
      success = job.perform
      job.errors.each do |er|
        errors << er
      end
      self.result = job.result # Push our work up the stack
      success
    end

    # Can we provision this service?
    # @return [Boolean]
    def ready_to_provision?
      volumes_ready?
    end

    # All required mounted volumes ready?
    # @return [Boolean]
    def volumes_ready?

      # An array of VolumeParam CSRNs
      available_volumes = provision_state[:volume_map].map { |i| i[:template] }
      if Rails.env.development?
        event.event_details.create!(
          data: "[DEBUG] #{product[:container_id]}\n\nrequired\n#{required_mountable_volumes.to_yaml}\n\navailable\n#{available_volumes.to_yaml}",
          event_code: "e63b84b01c9b375f"
        )
      end
      return true if (required_mountable_volumes - available_volumes).empty?

      # If we're looking for a volume CSRN, then we need to check the project
      return false if project.nil?
      remaining_volumes = required_mountable_volumes - available_volumes
      project_volumes = project.volumes.map { |i| i.csrn }
      return true if (remaining_volumes - project_volumes).empty? # Do we have volume CSRNs, and are they satisfied?

      (remaining_volumes - project_volumes).each do |i|
        event.event_details.create!(
          data: "[DEBUG] #{product[:container_id]} waiting on #{i}",
          event_code: "e63b84b01c9b375f"
        )
      end if Rails.env.development?
      false
    end

    ##
    # HasRequiredMountableVolumes?
    #
    # If we have mountable volumes, are they all build and ready for us?
    #
    # This is different than `volumes_available?` because this is looking to
    # see if they're actually built and ready to be mounted.
    #
    # @return [Boolean]
    # def has_required_mountable_volumes?
    #   # return true if required_mountable_volumes_not_in_order.empty?
    #   # return false if project.nil?
    #   ActiveRecord::Base.uncached do
    #     matched_volumes = []
    #     (required_mountable_volumes - required_mountable_volumes_not_in_order).each do |i|
    #       provision_state[:volumes].each do |ii| # Volume[]
    #         obj = Csrn.locate i
    #         # We allow passing either a Volume CSRN, or a VolumeParam csrn, so we need
    #         # to test for both.
    #         test_csrn = if obj.is_a?(Volume)
    #                       ii.csrn
    #                     elsif obj.is_a?(ContainerImage::VolumeParam)
    #                       ii.template&.csrn
    #                     end
    #         matched_volumes << ii.csrn if test_csrn == i
    #       end
    #     end
    #     if (required_mountable_volumes - matched_volumes).empty?
    #       true
    #     else
    #       event.event_details.create!(
    #         data: "#{product.to_yaml}\n\n#{provision_state.to_yaml}",
    #         event_code: "6e0a8d644baff8e4"
    #       )
    #     end
    #   end
    # end

    private

    # @return [Boolean]
    def valid?
      errors << "Missing project" unless project.is_a?(Deployment)
      errors << "Missing order" unless order.is_a?(Order)
      errors << "Missing event" unless event.is_a?(EventLog)
      errors << "Invalid image" unless image_exists?
      # errors << "Mounted volumes not available" unless volumes_available?
      errors.empty?
    end

    # @return [Boolean]
    def image_exists?
      image = ContainerImage.find_by id: product[:container_id]
      image && image.can_view?(order.user)
    end

    ##
    # Check to ensure all required volumes are available.
    #
    # The primary use case for this is if you set the action to mount, and
    # supplied the CSRN of a volume in the override volume config.
    #
    # @return [Boolean]
    # def volumes_available?
    #   ActiveRecord::Base.uncached do
    #     return true if required_mountable_volumes_not_in_order.empty?
    #     project_volumes = []
    #     if project
    #       project.volumes.each do |vol|
    #         next unless required_mountable_volumes_not_in_order.include?(vol.csrn)
    #         project_volumes << vol.csrn
    #       end
    #     end
    #     missing_vols = required_mountable_volumes - project_volumes
    #     errors << "Required mountable volumes will not be created by this order, and are not found in the project: #{missing_vols.join(', ')}"
    #     missing_vols.empty?
    #   end
    # end

    # Find volumes that we require to mount.
    #
    # Cloned volumes will not be included in this array.
    # Only applies to mounted volumes.
    #
    # @return [Array] Array of `Volume` and `ContainerImage::VolumeParam`
    def required_mountable_volumes
      image = ContainerImage.find_by id: product[:container_id]
      return [] if image.nil? # should never happen

      # Ignore volumes explicitly skipped.
      skip_volumes = product[:volume_config].filter_map {|i| i[:csrn] if i[:action] == "skip" }
      custom_mounted_volumes = product[:volume_config].filter_map {|i| i[:csrn] if i[:action] == "mount" }
      req_vols = image.volumes.filter_map do |i|
        next if skip_volumes.include?(i.csrn)
        if custom_mounted_volumes.include?(i.csrn) || i.source_volume
          i.csrn
        end
      end
      # for a volume CSRN instead of a template CSRN.
      custom_mounted_volumes.each do |i|
        req_vols << i unless req_vols.include?(i)
      end
      req_vols
    end

    # Determine which of our required volumes will be provided by the parent order.
    #
    # @return [Array] Array `VolumeParam`
    # def expected_mountable_volumes_from_order
    #   will_provide = []
    #   order.data[:raw_order].each do |i|
    #     image = ContainerImage.find_by id: i[:container_id]
    #     next if image.nil?
    #     image.volumes.each do |vol|
    #       will_provide << vol.csrn unless will_provide.include?(vol.csrn)
    #     end
    #   end
    #   will_provide
    # end

    # Determine which volumes won't be provided by this order.
    # @return [Array] Array of `Volume` and `ContainerImage::VolumeParam`
    # def required_mountable_volumes_not_in_order
    #   required_mountable_volumes - expected_mountable_volumes_from_order
    # end

  end
end
