module ProvisionServices
  ##
  # Provision a container Service
  # (does not actually create them on the node)
  #
  # * Generate the base service
  # * Create the subscription and associate products
  # * Create Containers
  #
  # @!attribute data
  #   @return [Hash]
  # @!attribute project
  #   @return [Deployment]
  # @!attribute event
  #   @return [EventLog]
  # @!attribute container_service
  #   @return [Deployment::ContainerService]
  # @!attribute image_variant
  #   @return [ContainerImage::ImageVariant]
  # @!attribute image
  #   @return [ContainerImage]
  # @!attribute user
  #   @return [User]
  # @!attribute region
  #   @return [Region]
  # @!attribute cpu
  #   @return [Float]
  # @!attribute memory
  #   @return [Integer]
  # @!attribute subscription
  #   @return [Subscription]
  # @!attribute qty
  #   @return [Integer]
  # @!attribute node
  #   @return [Node]
  # @!attribute errors
  #   @return [Array]
  # @!attribute result
  #   @return [Hash]
  class ContainerServiceProvisioner

    attr_accessor :data, # order provision data
                  :project,
                  :event,
                  :container_service,
                  :image,
                  :image_variant,
                  :user,
                  :project_user,
                  :region,
                  :cpu,
                  :memory,
                  :subscription,
                  :qty,
                  :node,
                  :source, # source container service
                  :errors,
                  :volume_maps,
                  ##
                  # Track what's been created
                  #
                  # {
                  #   containers: [],
                  #   subscriptions: [],
                  #   volumes: []
                  # }
                  :result,
                  :provision_state # Track what the parent hash


    # @param [User] user
    # @param [Deployment] project
    # @param [EventLog] event
    # @param [Hash] data
    def initialize(user, project, event, data)
      self.user = user
      self.project = project
      self.project_user = project&.user.nil? ? user : project.user
      self.subscription = nil
      self.event = event
      self.node = nil
      self.source = nil
      self.volume_maps = {}
      self.provision_state = {
        containers: [],
        subscriptions: [],
        load_balancers: [],
        volumes: [],
        volume_map: [], # [ { template: csrn, volume: csrn } ]
        volume_clones: [] # [ { vol_id: int, source_vol_id: int, source_snap: string } ]
      }
      self.result = {
        containers: [],
        subscriptions: [],
        load_balancers: [],
        volumes: [],
        volume_map: [], # [ { template: csrn, volume: csrn } ]
        volume_clones: [] # [ { vol_id: int, source_vol_id: int, source_snap: string } ]
      }
      # data = {
      #   qty: Integer,
      #   label: String,
      #   region_id: Integer,
      #   image_variant_id: Integer,
      #   product_id: Integer,
      #   cpu: Decimal,
      #   memory: Integer,
      #   settings: {},
      #   volume_config: [],
      #   external_id: String
      # }
      self.data = data
      self.errors = []

      self.qty = 1 # TODO: Support `qty` of containers during order process.

      # FREE images are being set in `BuildOrderService`
      self.cpu = 0
      self.memory = 0
    end

    # @return [Boolean]
    def perform
      return rollback! unless valid?
      return rollback! unless init_subscription?
      return rollback! unless init_service!
      return rollback! unless init_service_plugins!
      return rollback! unless select_node!
      return rollback! unless init_private_lbs!
      return rollback! unless setup_service_config!
      return rollback! unless build_volumes!
      p_region = subscription.nil? ? BillingPackage.new(cpu: 1, memory: 512) : subscription.package
      1.upto(qty).each do
        new_container = ProvisionServices::ContainerProvisioner.new(container_service)
        if region.has_clustered_storage?
          if subscription.package.nil?
            errors << "Unable to provision container, missing package"
            next
          end
          new_container.node = region.find_node p_region
          if new_container.node.nil?
            errors << "Unable to place container on node"
            next
          end
        else
          new_container.node = node
        end
        unless new_container.perform
          new_container.errors.each do |i|
            errors << i
          end
          errors << "Error building container for service #{container_service&.name}" if new_container.errors.empty?
          return rollback!
        end
        result[:containers] << new_container.container if new_container.container
      end
      finalize!
    end

    private

    # Generate service settings and params
    #
    # This needs to be run AFTER:
    # * The init service method
    # * generate internal LB
    #
    # This will not generate env params
    #
    # @return [Boolean]
    def setup_service_config!
      unless container_service.gen_settings_config!(event, data[:settings])
        errors << "failed to generate service setting params"
        return false
      end
      unless container_service.gen_ingress_rules!(event)
        errors << "failed to generate ingress rules"
        return false
      end
      if source
        unless container_service.gen_cloned_config!(source, event)
          errors << "failed to generate cloned env configuration for #{source.csrn}"
          return false
        end
      end
      true
    end

    # @return [Boolean]
    def finalize!
      # Setup network policy for service
      NetworkWorkers::ServicePolicyWorker.perform_async container_service.id
      true
    end

    # Select the node this service will use
    #
    # if the service has no volumes, then we can allow it to run across nodes. Otherwise,
    # we will pin them all to the same node.
    def select_node!
      return node unless node.nil?
      return true if region.has_clustered_storage?

      # Find any volumes that have been marked as skip during the order process.
      skip_volumes = data[:volume_config].filter_map {|i| i[:csrn] if i[:action] == "skip" }

      # TODO: Try to first select volumes created in this order, and then fallback to volumes
      #       created within the project.

      # Returns a list of volume resource names
      # this includes both volumes we need to create for ourselves, but also ones we reference from other containers
      req_volume_templates = container_service.container_image.volumes.filter_map { |i| i.csrn unless skip_volumes.include?(i.csrn) }

      # Based on what we need, and what we have, figure out if we're already bound to a specific node(s).
      have_nodes = []
      project.volumes.where.not(template: nil).each do |i|
        next unless req_volume_templates.include?(i.template.csrn)
        # for local storage, volumes will only ever have 1 node, but we still need to select it from the array.
        have_nodes << i.nodes.first unless have_nodes.include?(i.nodes.first)
      end

      if have_nodes.count > 1
        errors << "Service requires volumes found on multiple nodes, unable to provision."
        return false
      elsif have_nodes.count == 1
        self.node = have_nodes.first
        return true
      end


      if container_service.container_image.volumes.empty?
        self.node = nil
      else
        # Free containers (phpMyAdmin) won't have a subscription
        if subscription && subscription.package.nil?
          errors << "Missing package, unable to find node"
          return false
        end
        p_region = subscription.nil? ? BillingPackage.new(cpu: 1, memory: 512) : subscription.package
        n = container_service.nodes.empty? ? region.find_node(p_region) : container_services.nodes.first
        if n.nil?
          errors << "Expected to have a node, but nil was returned."
          event.event_details.create!(
            data: region.context.to_yaml,
            event_code: "57e27d7a868e5e96"
          ) unless region.context.empty?
          return false
        end
        self.node = n
      end
      true
    end

    # @return [Boolean]
    def build_volumes!
      volume_driver = if container_service.container_image.force_local_volume
                        'local'
                      else
                        container_service.region.volume_backend
                      end

      skip_volumes = data[:volume_config].filter_map { |i| i[:csrn] if i[:action] == "skip" }

      container_service.container_image.volumes.each do |vol|
        next if skip_volumes.include?(vol.csrn)

        # Sanity check -- we're not going to mount multiple volumes into the same path.
        next if container_service.volume_maps.where(mount_path: vol.mount_path).exists?

        existing_volume = nil # Volume
        project.volumes.where.not(template: nil).each do |i|
          if i.template.csrn == vol.csrn
            existing_volume = i
            break
          end
        end

        source_snapshot = nil
        vol_action = existing_volume ? 'mount' : 'create'
        mount_ro = vol.mount_ro

        # Volume configuration overrides for this specific order.
        custom_vol_req = data[:volume_config].select { |i| i[:csrn] == vol.csrn }[0]

        if custom_vol_req
          unless custom_vol_req[:source].blank?
            existing_volume = Csrn.locate(custom_vol_req[:source])

            # Locate volume in provisioned volumes
            if existing_volume.is_a?(ContainerImage::VolumeParam)
              mapped_vol = provision_state[:volume_map].select { |i| i[:template] == existing_volume.csrn }[0]
              if mapped_vol
                existing_volume = Csrn.locate mapped_vol[:volume]
              end
            end

            # Locate volume in project
            if existing_volume.is_a?(ContainerImage::VolumeParam) && project
              project.volumes.each do |pvol|
                if pvol.template&.csrn == existing_volume.csrn
                  existing_volume = pvol
                  break
                end
              end
            end

            # If we still didn't find it, error out.
            if existing_volume.is_a?(ContainerImage::VolumeParam)
              errors << "Failed to locate requested volume: #{custom_vol_req[:source]} for #{container_service.container_image.label}"
              return false
            end

          end
          vol_action = custom_vol_req[:action] unless custom_vol_req[:action].blank?
          unless custom_vol_req[:mount_ro].blank?
            mount_ro = ActiveRecord::Type::Boolean.new.cast(custom_vol_req[:mount_ro])
          end
          source_snapshot = custom_vol_req[:snapshot] unless custom_vol_req[:snapshot].blank?
        end

        new_vol = if existing_volume && vol_action == 'mount'
                    existing_volume
                  else
                    container_service.volumes.new(
                      label: vol.label,
                      user: container_service.deployment.user,
                      deployment: project,
                      borg_enabled: vol.borg_enabled,
                      borg_freq: vol.borg_freq,
                      borg_strategy: vol.borg_strategy,
                      borg_keep_hourly: vol.borg_keep_hourly,
                      borg_keep_daily: vol.borg_keep_daily,
                      borg_keep_weekly: vol.borg_keep_weekly,
                      borg_keep_monthly: vol.borg_keep_monthly,
                      borg_keep_annually: vol.borg_keep_annually,
                      borg_backup_error: vol.borg_backup_error,
                      borg_restore_error: vol.borg_restore_error,
                      borg_pre_backup: vol.borg_pre_backup,
                      borg_post_backup: vol.borg_post_backup,
                      borg_pre_restore: vol.borg_pre_restore,
                      borg_post_restore: vol.borg_post_restore,
                      borg_rollback: vol.borg_rollback,
                      enable_sftp: vol.enable_sftp,
                      region: container_service.region,
                      volume_backend: volume_driver,
                      template: vol
                    )
                  end

        primary_mount = false
        provision_volume_job = nil
        if %w(create clone).include?(vol_action)
          ##
          # Ensure that the volume is allowed on _all_ nodes in the region when clustering.
          if volume_driver == 'nfs'
            # We need to ensure all nodes have the volume
            container_service.region.nodes.each do |node|
              new_vol.nodes << node
            end
          elsif node
            new_vol.nodes << node
          end

          unless new_vol.save
            errors << "Failed to create volume: #{new_vol.errors.full_messages.join(' ')}"
            return false
          end
          result[:volumes] << new_vol
          result[:volume_map] << { template: new_vol.template.csrn, volume: new_vol.csrn }
          primary_mount = true
          provision_volume_job = VolumeServices::ProvisionVolumeService.new(new_vol, event)

          if vol_action == 'clone' # Regardless of state, pass if cloning.
            result[:volume_clones] << {
              vol_id: new_vol.id,
              source_vol_id: existing_volume&.id,
              source_snap: source_snapshot.blank? ? nil : source_snapshot
            }
          end
        end

        vol_map = container_service.volume_maps.new(
          volume: new_vol,
          mount_path: vol.mount_path,
          mount_ro: mount_ro,
          is_owner: primary_mount
        )
        unless vol_map.save
          errors << "Failed to create volume map: #{vol_map.errors.full_messages.join(' ')}"
          return false
        end

        if provision_volume_job
          unless provision_volume_job.perform
            errors << "Error provisioning volumes."
            return false
          end
        end

      end
    rescue => e
      ExceptionAlertService.new(e, '38e27fb46115333a').perform
      errors << "Fatal error provisioning volumes: #{e.message}"
      false
    end

    # @return [Boolean]
    def rollback!
      result[:containers].each do |c|
        c.subscription.destroy if c.subscription
        c.delete_from_node! event
        c.destroy
      end
      result[:subscriptions].each do |s|
        s.destroy
      end
      result[:volumes].each do |v|
        v.update_attribute :to_trash, true
      end
      # If we have no containers, then delete the entire service
      if container_service
        container_service.reload
        container_service.destroy if container_service.containers.empty?
      end
      false
    end

    # @return [Boolean]
    def valid?
      errors << "Invalid qty" if qty < 1
      errors << "Missing project" if project.nil?
      errors << "Invalid user" if user.nil?
      return false unless errors.empty?
      unless user.can_order_containers? qty
        errors << "User over quota"
        return false
      end
      if data[:region_id].blank?
        errors << "Missing region ID"
        return false
      end
      self.region = Region.find_by(id: data[:region_id])
      if region.nil?
        errors << "Unknown region"
        return false
      end
      unless region.allow_user? user
        errors << "Invalid region"
        return false
      end
      self.image_variant = ContainerImage::ImageVariant.find_by(id: data[:image_variant_id])
      if image_variant.nil?
        errors << "Unknown image: #{data[:image_variant_id]}"
        return false
      end
      self.image = image_variant.container_image
      unless image.can_view? user
        errors << "Invalid image: #{data[:image_variant_id]}"
        return false
      end
      unless data[:source_csrn].blank?
        s = Csrn.locate data[:source_csrn]
        if s && s.is_a?(Deployment::ContainerService)
          if s.can_view?(user)
            self.source = s
          else
            errors << "User does not have permission to clone #{data[:source_csrn]}"
          end
        else
          errors << "Invalid source service #{data[:source_csrn]}"
          return false
        end
      end
      true
    end

    def init_subscription?
      if image.is_free
        self.cpu = data[:cpu]
        self.memory = data[:memory]
        return true
      end
      image_product = if image.product
                        image.product.allow_user?(project_user) ? image.product : nil
                      else
                        nil
                      end
      service_products = []

      service_products << image_product if image_product

      # Init any addon products (e.g. non-optional image plugins)
      # 1. If an addon has an associated product, and it's optional + present in the addons array,
      #    then we'll create a subscription for it. (User will be charged).
      # 2. If an addon is not optional, and has a product assigned to it, then the user will
      #    be charged for it, regardless of it's presence in the array.
      image.container_image_plugins.active.each do |i|
        next if i.product.nil?
        next unless data[:addons].include?(i.id.to_s) || !i.is_optional
        service_products << i.product
      end

      bw = Product.lookup(project_user.billing_plan, 'bandwidth')
      if bw.nil?
        errors << "Missing bandwidth product in billing plan."
        return false
      end
      service_products << bw
      disk = Product.lookup(project_user.billing_plan, 'storage')
      if disk.nil?
        errors << "Missing storage product in billing plan."
        return false
      end
      local_disk = Product.lookup(project_user.billing_plan, 'local_disk')
      if local_disk.nil?
        errors << "Missing temporary storage product in billing plan."
        return false
      end
      service_products << disk
      service_products << local_disk
      if data[:product_id]
        product = Product.find_by(id: data[:product_id])
        if product.nil?
          errors << "Unknown package"
          return false
        elsif !product.allow_user? project_user
          errors << "Invalid package"
          return false
        elsif product.package.nil?
          errors << "Product has no package"
          return false
        end
        service_products << product
        self.cpu = product.package.cpu
        self.memory = product.package.memory
      else
        errors << "Missing container resource constraints"
      end
      return false unless errors.empty?

      self.subscription = project_user.subscriptions.new(
        external_id: data[:external_id],
        active: false
      )
      subscription.current_audit = event.audit if event&.audit
      if subscription.save
        result[:subscriptions] << subscription
      else
        errors << subscription.errors.full_messages.join(' ')
        return false
      end
      service_products.each do |p|
        sp = subscription.add_product! p
        unless sp.errors.empty?
          errors << "Failed to create subscription product for: #{p.id}"
        end
      end

      unless errors.empty?
        subscription.destroy
        self.subscription = nil
        return false
      end
      true
    end

    # @return [Boolean]
    def init_service!
      service_name = NamesGenerator.name(project.id)
      self.container_service = project.services.new(
        image_variant: image_variant,
        name: service_name,
        label: data[:label].blank? ? service_name : data[:label],
        cpu: cpu,
        memory: memory,
        region: region,
        command: image.command
      )
      container_service.current_audit = event.audit if event&.audit
      container_service.initial_subscription = subscription if subscription
      unless container_service.save
        errors << container_service.errors.full_messages.join(' ')
        return false
      end
      event.container_services << container_service
      true
    end

    ##
    # Create image plugin
    #
    # Regardless of active/available state, we still create the plugin
    # so that we can activate it later.
    #
    # @return [Boolean]
    def init_service_plugins!
      image.container_image_plugins.each do |i|
        plugin_active = if data[:addons].include?(i.id)
                          true
                        else
                          i.is_optional ? false : true
                        end
        p = container_service.service_plugins.new(
          container_image_plugin: i,
          active: plugin_active,
          is_optional: i.is_optional
        )
        unless p.save
          errors << "Error saving plugin #{i.name} | #{p.errors.full_messages.join(", ")}"
          return false
        end
      end
      true
    end

    # @return [Boolean]
    def init_private_lbs!
      lb_job = ProvisionServices::IngressControllerProvisioner.new(container_service, event)
      unless lb_job.perform
        errors << "Error generating private Load Balancer: #{lb_job.errors.join(' ')}"
      end
      result[:load_balancers] = lb_job.load_balancers
      lb_job.errors.empty?
    end

  end
end
