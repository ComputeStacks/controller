module NetworkSubnetManager
  extend ActiveSupport::Concern

  included do
    before_validation :ensure_no_overlap
    before_validation :prevent_updates_while_in_use, on: :update
    after_save :cascade_network_changes
  end

  ##
  # Find next available IP
  def next_ip
    ActiveRecord::Base.uncached do
      a = to_addr
      # network, gateway, broadcast
      in_use = addresses_in_use
      0.upto(a.len - 2) do |i|
        ip = a.nth(i)
        next if in_use.include?(ip.addr)
        return "#{ip.to_s}/32"
      end
    end
    nil
    ##
    # range = subnet.to_range
    #
    # # Bring some randomness into the ip selection process.
    # rstep = rand(1..3)
    # flip_check = rand(1..2).even?
    #
    # if flip_check
    #   range.step(rstep).each do |addr|
    #     reload
    #     used = addresses.pluck(:cidr)
    #     used_on_node = active_in_use
    #     next if restricted?(addr)
    #     next if used_on_node.include?(addr)
    #     return addr.to_s unless used.include?("#{addr}/32")
    #   end
    # else
    #   range.step(rstep).reverse_each do |addr|
    #     reload
    #     used = addresses.pluck(:cidr)
    #     used_on_node = active_in_use
    #     next if restricted?(addr)
    #     next if used_on_node.include?(addr)
    #     return addr.to_s unless used.include?("#{addr}/32")
    #   end
    # end
    # nil
  end

  private

  # Ensure we don't create overlapping networks within the same AZ
  def ensure_no_overlap
    return unless subnet_changed?
    return if region.nil?
    region.networks.each do |n|
      next if n.parent_network.nil? # only parent networks
      next if n.id == id # don't look out ourselves
      if n.subnet.include?(subnet) || subnet.include?(n.subnet)
        errors.add :subnet, 'overlaps with an existing network in this availability zone'
      end
    end
  end

  # Don't allow updates If this network has addresses in use.
  def prevent_updates_while_in_use
    return unless subnet_changed?

    # Check for container addresses
    unless addresses.empty?
      errors.add :subnet, 'has addresses in use, unable to modify network'
    end

    # Check for dependent networks
    unless child_networks.empty?
      # With deployments
      if child_networks.where.not(deployment_id: nil).exists?
        errors.add :subnet, 'has child networks in use, unable to modify network'
      end
      # check for active (on node) networks
      if child_networks.active.exists?
        errors.add :subnet, 'has child networks on node, unable to modify network'
      end
    end


  end

  def cascade_network_changes
    return if has_clustered_networking?
    return unless subnet_previously_changed?
    return unless parent_network.nil? # only parents can cascade!
    # Delete existing unused networks
    child_networks.where(deployment_id: nil, active: false).delete_all

    s = to_addr
    count = s.subnet_count(region.p_net_size) - 1 # start at 0.
    0.upto(count) do |i|
      net = s.nth_subnet region.p_net_size, i
      next if child_networks.where(subnet: net.to_s).exists?
      child_networks.create!(
        name: "#{name}#{i}",
        label: "#{name}#{i}",
        is_shared: false,
        active: false,
        region: region,
        subnet: net.to_s
      )
    end
  end

end
