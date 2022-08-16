# BuildOrderService
#
# This replaces the old OrderBuilder service and now returns a completed order, or errors,
# instead of creating the order, and _then_ processing the data.
#
# By default, this will only create the order. To also process the order,
# be sure to set `process_order = true`.
#
class BuildOrderService

  attr_accessor :audit,
                :event,
                :errors,
                :params, # Order data
                :order,
                :process_order,
                :user,
                :project_user,
                :redirect_url, # built order!

                ## Additional local params ##
                :project,
                :location,
                :region

  def initialize(audit, data = {})
    self.process_order = false
    self.order = nil
    self.audit = audit
    self.user = audit.user
    self.project_user = audit.user
    self.params = data
    self.event = nil # can be optionally set, otherwise it will be created.
    self.errors = []

    # initialize other params
    self.project = nil
    self.location = nil
    self.region = nil
    self.redirect_url = nil
  end

  def perform
    deprecation_clean_up!

    # Will set `project_user` here, if `user` is a collaborator.
    return false unless valid_order?

    return false unless valid_container_params?
    return false unless within_quota?

    # Build order data from params

    formatted_container_data = []

    params[:containers].each do |c|
      item = {
        product_type: 'container',
        source: c[:source], # Source service CSRN
        label: c[:name],
        container_id: c[:image_id].to_i,
        qty: c[:qty],
        domains: c[:domains] ? c[:domains] : [],
        resources: c[:resources],
        params: {},
        # c[:volumes] = [
        #   {
        #     csrn: String,
        #     action: String<create,clone,mount,skip>,
        #     source: String,
        #     snapshot: String,
        #     mount_ro: Bool
        #   }
        # ]
        volume_config: c[:volumes].nil? ? [] : c[:volumes]
      }
      # Merge params
      if c[:params] && c[:params].is_a?(Array)
        c[:params].each do |i|
          item[:params][i[:key]] = { value: i[:value], type: i[:type] }
        end
      end
      formatted_container_data << item
    end

    new_order_data = {
      raw_order: formatted_container_data,
      project: {
        id: project&.id,
        name: project.nil? ? params[:project_name] : project.name,
        skip_ssh: params[:skip_ssh] ? true : false
      },
      region_id: region.id,
      location_id: location.id,
      load_balancer_ip: region.load_balancer&.public_ip
    }

    # Allow us to also edit an existing order
    if order
      order.data = new_order_data
    else
      self.order = Order.new(
        user: audit.user,
        current_audit: audit,
        data: new_order_data,
        location_id: location&.id
      )
      if project
        order.deployment = project
      end

      # When passing the `:id` from params, this is expected to be the ID
      # of the newly created order.
      order.id = params[:id] if params[:id]
    end

    order.external_id = params[:external_id] if params[:external_id]

    if order.valid? && order.save

      # Update Audit Object
      # order.audits << audit  # this won't add the `rel_model` portion, so we need to set it by updating the audit record directly.
      audit.update(rel_uuid: order.id, rel_model: 'Order')

      if process_order
        order.pending!
        # Process right away
        ProcessOrderWorker.perform_async order.to_global_id.to_s, audit.to_global_id.to_s
      end
    else
      order.errors.full_messages.each do |er|
        errors << er
      end
    end
    errors.empty?
  end

  private

  def requested_packages
    products = []
    params[:containers].each_with_index do |c,i|
      product_id = c.dig(:resources, :product_id).nil? ? nil : c.dig(:resources, :product_id).to_i
      next if product_id.nil?
      p = Product.find_by id: product_id
      next if p.nil? || p.package.nil?
      products << p.package
    end
    products
  end

  def within_quota?
    requested_containers = 0
    params[:containers].each do |i|
      requested_containers += i[:qty]
    end
    user.can_order_containers? requested_containers
  end

  # First round of basic sanity checks
  def valid_order?
    errors << "Missing user" if user.nil?
    errors << "Missing project name" if params[:project_name].blank?
    errors << "Missing containers" if params[:containers].nil? || params[:containers].empty?
    self.project = if params[:project_id].blank? || user.nil?
                     nil
                   else
                     Deployment.find_for(user, { id: params[:project_id] })
                   end
    errors << "Unknown project" if project.nil? && user && !params[:project_id].blank?
    return false unless errors.empty? # Stop here before proceeding
    self.project_user = project.nil? ? user : project.user
    # 1 location per project!
    self.location = if project && !project.locations.empty? # Choose existing project location
                      project.locations.first
                    elsif params[:location_id] # Location requested
                      Location.find_for_user(params[:location_id], project_user)
                    else # Pick next available location
                      Location.available_for(project_user, 'container').first
                    end
    errors << "Unknown Region" if location.nil?
    self.region = if project && !project.locations.empty?
                    project.regions.first
                  elsif location
                    location.next_region requested_packages, project_user, 1
                  else
                    nil
                  end
    errors << "There are no availability zones available" if region.nil?
    errors.empty?
  end

  def valid_container_params?
    included_image_ids = params[:containers].map {|i| i[:image_id].to_i if i[:image_id]}
    if project  # Include existing images when performing dependency checks
      project.container_images.each { |i| included_image_ids << i.id }
    end

    # Expected params
    req_params = %i(image_id name resources params source volumes)

    params[:containers].each_with_index do |c,i|

      # Match array of instance variables and ensure we have the same array
      unless c != req_params
        errors << "Incomplete container params. Have: #{c.to_s}, need: #{req_params.to_s}"
        next
      end

      # Validate image
      img = ContainerImage.find_for(user, {id: c[:image_id]})
      if img.nil?
        errors << "Invalid image. Image ID: #{c[:image_id]} | #{c[:name]}."
        next
      end

      # Validate source (if applicable)
      unless c[:source].blank?
        source_service = Csrn.locate c[:source]
        if source_service.nil?
          errors << "Invalid source #{c[:source]}"
          next
        end
        unless source_service.is_a?(Deployment::ContainerService)
          errors << "Expected source to be a container service #{c[:source]}"
          next
        end
        unless source_service.can_view?(project_user)
          errors << "User does not have permission to clone #{c[:source]}"
          next
        end
      end

      product_id = c.dig(:resources, :product_id).nil? ? nil : c.dig(:resources, :product_id).to_i

      # If this is a free image, then set the resources here and ignore what the user asks for.
      if img.is_free
        c[:resources] = {
          cpu: img.min_cpu.zero? ? 1.0 : min_cpu,
          memory: img.min_memory.zero? ? 768 : min_memory
        }
        next
      elsif product_id.nil?
        errors << "Missing package selection for #{img.label}"
        next
      end

      c[:qty] = 1 if c[:qty].to_i.zero?
      qty = c[:qty].to_i

      cpu = c.dig(:resources, :cpu).nil? ? nil : c.dig(:resources, :cpu).to_i
      mem = c.dig(:resources, :memory).nil? ? nil : c.dig(:resources, :memory).to_i

      # Check and validate resources
      if product_id.nil?
        if cpu.nil? || mem.nil?
          errors << "Missing container resources for #{c[:image_id]} | #{c[:name]}. Have CPU #{cpu}, MEM #{mem}"
        else
          # Validate requested resources with
          if cpu < img.min_cpu
            errors << "Invalid CPU. Image requires at least #{img.min_cpu}."
          end
          if mem < img.min_memory
            errors << "Invalid Memory. Image requires at least #{img.min_memory} MB."
          end
        end
      else
        product_check = Product.find_by(id: product_id)
        unless product_check
          errors << "Unknown package: #{product_id}"
          next
        end
        # price_resource = product_check.price_lookup(user, region)

        # Ensure user has permission to use this product
        unless product_check.allow_user?(project_user)
          errors << "Invalid package: #{product_id}"
          next
        end

        package = product_check.package

        # Ensure product actually has a package
        if package.nil?
          errors << "Product is missing package config data: #{product_check.label}"
          next
        end

        c[:resources][:cpu] = package.cpu
        c[:resources][:memory] = package.memory
        c[:resources][:product_id] = product_id # ensure this exists!

        # Validate resources against container image
        if package.cpu < img.min_cpu || package.memory < img.min_memory
          errors << "Package #{product_check.label} not suitable for the image #{img.label}. CPU must be greater than #{img.min_cpu}, and memory must be greater than #{img.min_memory} MB."
          next
        end
      end # END resource check

      if qty.to_i < 1
        errors << "Invalid qty for #{c[:image_id]} | #{c[:name]}"
      end

      # Validate passed parameters
      provided_params = c[:params].nil? ? [] : c[:params].map {|param| param[:key]}
      img.setting_params.where(param_type: 'static').each do |ii|
        errors << "Missing parameter #{ii.name} for #{c[:name]} (#{c[:image_id]})" unless provided_params.include?(ii.name)
      end

      # validate dependent containers
      img_deps = img.dependencies.pluck(:id)
      unless (img_deps - included_image_ids).empty?
        errors << "Missing required dependent services. Have #{(img_deps & included_image_ids).to_s}, Need #{(img_deps - included_image_ids).to_s}"
      end # END dependency check

      # Validate provided domain names
      if c[:domains].is_a?(Array)
        c[:domains].each do |domain|
          if Deployment::ContainerDomain.where(domain: domain).exists?
            errors << "Domain #{domain} already in use."
          end
        end
      end

      # Validate volume parameters
      if c[:volumes].is_a?(Array)

        have_source_ids = c[:volumes].filter_map { |i| i[:source] if i[:source] && i[:source] =~ /template/ }

        c[:volumes].each do |i|
          next if i[:action] == 'create'
          id = i[:csrn]
          action = i[:action]
          source = i[:source]
          snapshot = i[:snapshot]
          vol = Csrn.locate id

          # For volumes that are created in this order, vol will be a ContainerImage::VolumeParam.
          # Verify that this volume param exists in this order.
          if action == 'mount'
            unless have_source_ids.include?(source)
              errors << "Requested mounted volume template is not found in this order"
            end
            next
          end

          # Ensure passed parameters are compatible with requested action
          case action
          when "create"
            errors << "Create action is not compatible with a source volume" unless source.blank?
            errors << "Create action is not compatible with a snapshot" unless snapshot.blank?
          when "skip"
            errors << "Skip action is not compatible with a source volume" unless source.blank?
            errors << "Skip action is not compatible with a snapshot" unless snapshot.blank?
          when "mount"
            errors << "Mount action is not compatible with a snapshot" unless snapshot.blank?
            errors << "Mount action requires a source volume" if source.blank?
          when "clone"
            errors << "Clone action requires a source volume" if source.blank?
          else
            errors << "Unknown action: #{action.blank? ? 'null' : action}"
          end

          # Ensure we have a source volume
          if source.blank? && !snapshot.blank?
            errors << "#{action} with a snapshot requires a source volume"
          end

          # Volume & Snapshot specific validations
          unless source.blank?

            # Ensure volume exists and user has permission to access it
            source_vol = Csrn.locate source
            if source_vol.nil? || !source_vol.can_view?(user)
              errors << "Unknown source volume #{source}"
              source_vol = nil # wipe found volume if we don't have permission to use it.
            end

            if source_vol

              # Mount: Ensure volume exists in the current project
              if action == "mount" && source_vol.deployment != project
                errors << "You may only mount volumes from the same project"
              end

              # Clone with Snapshot: Ensure snapshot exists for volume
              if action == "clone" && !snapshot.blank?
                locate_snapshot = vol.list_archives.select { |i| i[:id] == snapshot }
                errors << "Snapshot not found" if locate_snapshot.empty?
              end

            end
          end
        end
      end
    end
    errors.empty?
  end

  # Normalize values from deprecated terms to new ones!
  #
  # Currently will translate:
  # * `:container_image_id` to `:image_id`
  # * `:package_id` to `:product_id`
  #
  def deprecation_clean_up!

    params[:containers].each do |i|
      # `:container_image_id` to `:image_id`
      i[:image_id] = i[:container_image_id].to_i if i[:container_image_id]

      next if i.dig(:resources, :product_id) # all OK

      # `:package_id` to `:product_id`
      i[:resources] = {} unless i[:resources].is_a?(Hash)
      i[:resources][:product_id] = i.dig(:resources, :package_id) if i.dig(:resources, :package_id)
      i[:resources][:product_id] = i[:product_id] if i[:product_id]
      i[:resources][:product_id] = i[:package_id] if i[:package_id]

    end if params[:containers].is_a?(Array)
  end

end
