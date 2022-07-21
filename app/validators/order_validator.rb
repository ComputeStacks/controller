class OrderValidator < ActiveModel::Validator
  def validate(order)
    quota_check!(order)
    v_deployment(order) unless order.order_data['project'].nil?
  end

  def quota_check!(order)
    if order.order_data['project']
      container_orders = order.order_data['raw_order'].map { |i| i if i['product_type'] == 'container' }
      unless order.user.can_order_containers?(container_orders.count)
        order.errors.add(:base, "Over quota, unable to process #{container_orders.count} containers.")
      end
    end
  end

  def v_deployment(order)
    location = Location.find_by id: order.order_data['location_id']
    if location.nil?
      order.errors.add(:base, 'Unknown Location.')
    else
      # Verify we have access to this location
      available_locations = Location.available_for(order.user, 'container')
      unless available_locations.map { |i| i.id }.include?(location.id)
        order.errors.add(:base, "#{location.name} is not available for provisioning.")
      end

      # Ensure a node exists with enough CPU
      # Find max cpu we need.
      max_cpu = 0.0
      order.order_data['raw_order'].each do |i|
        image = ContainerImage.find_by(id: i['container_id'])
        if image.nil?
          errors.add(:base, "Unknown image.")
          next
        end
        product = Product.find_by(id: i.dig('product', 'id'))
        cpu = 0.0
        mem = 0
        if product.nil? || product.package.nil?
          if i.dig('resources', 'cpu').nil? || i.dig('resources', 'memory').nil?
            order.errors.add(:base, "Invalid resources.")
            next
          else
            cpu = i.dig('resources', 'cpu').to_f
            mem = i.dig('resources', 'memory').to_i
            max_cpu = cpu unless cpu < max_cpu
          end
        else
          cpu = product.package.cpu
          mem = product.package.memory
          max_cpu = product.package.cpu unless product.package.cpu < max_cpu
        end
        if (cpu < image.min_cpu) || (mem < image.min_memory)
          order.errors.add(:base, "Error! This image requires at least #{image.min_cpu} CPU, and #{image.min_memory} MB of ram.")
        end
        next if product.nil? || product.package.nil? # Product validation is handled at a different stage. There are valid reasons why this is nil.
      end

      ##
      # Determine if we have nodes that can support the requested number of CPUs.
      #
      # TODO: Rewrite for Prometheus Metrics
      #
      # This will err on the side of caution and approve orders if we're unsure of the current state of nodes.
      # Containers will ultimately fail to start if the requested number of cores is greater than what's available on the host.
      # has_node = false
      # location.nodes.available.each do |node|
      #   begin # Use begin/rescue to catch nil or missing values.
      #     c = node.metrics_client
      #     # Allow situations where we lost access to the metrics database to proceed.
      #     if c.nil? || c.info.empty?
      #       has_node = true
      #       next
      #     end
      #     node_cpu_count = c.info[:cpus]
      #     # Accept CPUs of 0 -- this can happen if metrics database is temporarily missing data.
      #     has_node = true if node_cpu_count.zero? || node_cpu_count >= max_cpu
      #   rescue
      #     next
      #   end
      # end
      # order.errors.add(:base, "There are no nodes available with enough CPU Cores to fill this order.") unless has_node
    end
  end
end
