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
        volume_map: [], # [ { template: csrn, volume: csrn } ]
        volume_clones: [] # [ { vol_id: int, source_vol_id: int, source_snap: string } ]
      }

      # The result hash that's getting added to each cycle.
      self.provision_state = {
        containers: [],
        subscriptions: [],
        load_balancers: [],
        volumes: [],
        volume_map: [], # [ { template: csrn, volume: csrn } ]
        volume_clones: [] # [ { vol_id: int, source_vol_id: int, source_snap: string } ]
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
          external_id: product[:remote_service_id],
          source_csrn: product[:source] # CSRN of source container service
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

  end
end
