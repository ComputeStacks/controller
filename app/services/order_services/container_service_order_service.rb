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
        volumes: []
      }

      # The result hash that's getting added to each cycle.
      self.provision_state = {
        containers: [],
        subscriptions: [],
        load_balancers: [],
        volumes: []
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
          volume_config: product[:volumes].nil? ? [] : product[:volumes],
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

    ##
    # HasRequiredMountableVolumes?
    #
    # If we have mountable volumes, are they all build and ready for us?
    #
    # This is different than `volumes_available?` because this is looking to
    # see if they're actually built and ready to be mounted.
    #
    # @return [Boolean]
    def has_required_mountable_volumes?
      return true if required_mountable_volumes_not_in_order.empty?
      return false if project.nil?
      matched_volumes = []
      (required_mountable_volumes - required_mountable_volumes_not_in_order).each do |i|
        provision_state[:volumes].each do |ii|
          next unless ii.csrn == i
          matched_volumes << ii.csrn
        end
      end
      (required_mountable_volumes - matched_volumes).empty?
    end

    private

    # @return [Boolean]
    def valid?
      errors << "Missing project" unless project.is_a?(Deployment)
      errors << "Missing order" unless order.is_a?(Order)
      errors << "Missing event" unless event.is_a?(EventLog)
      errors << "Invalid image" unless image_exists?
      errors << "Mounted volumes not available" unless volumes_available?
      errors.empty?
    end

    # @return [Boolean]
    def image_exists?
      image = Deployment::ContainerImage.find_by id: product[:container_id]
      image && image.can_view?(order.user)
    end

    # Determine if it's possible to provision this with the required mounted volumes.
    # The idea here is to check both this order, and what's already been provisioned
    # in the project, and see if all requested mounted volumes are present, or will be present.
    #
    # @return [Boolean]
    def volumes_available?
      return true if required_mountable_volumes_not_in_order.empty?
      return false if project.nil?
      project_volumes = []
      project.volumes.each do |vol|
        next if vol.template.nil?
        next unless required_mountable_volumes_not_in_order.include?(vol.template.csrn)
        project_volumes << vol.template.csrn
      end
      missing_vols = required_mountable_volumes - matched_volumes
      errors << "Required mountable volumes will not be created by this order, and are not found in the project: #{missing_vols.join(', ')}"
      missing_vols.empty?
    end

    # Find volumes that we require to mount.
    # @return [Array]
    def required_mountable_volumes
      image = Deployment::ContainerImage.find_by id: product[:container_id]
      return [] if image.nil? # should never happen

      # Ignore volumes explicitly skipped.
      skip_volumes = product[:volume_config].filter_map {|i| i[:csrn] if i[:action] == "skip" }
      custom_mounted_volumes = product[:volume_config].filter_map {|i| i[:csrn] if i[:action] == "mount" }
      image.volumes.filter_map do |i|
        next if skip_volumes.include?(i.csrn)
        if custom_mounted_volumes.include?(i.csrn) || i.source_volume
          i.csrn
        end
      end
    end

    # Determine which of our required volumes will be provided by the parent order.
    # @return [Array]
    def expected_mountable_volumes_from_order
      will_provide = []
      order.data[:raw_order].each do |i|
        image = Deployment::ContainerImage.find_by id: i[:container_id]
        next if image.nil?
        image.volumes.each do |vol|
          will_provide << vol.csrn unless will_provide.include?(vol.csrn)
        end
      end
      will_provide
    end

    # Determine which volumes won't be provided by this order.
    # @return [Array]
    def required_mountable_volumes_not_in_order
      required_mountable_volumes - expected_mountable_volumes_from_order
    end

  end
end
