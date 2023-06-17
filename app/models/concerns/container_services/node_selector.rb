# Manage node selection process for container services.
#
# Only used for services that need to be pinned to the same host.
#
module ContainerServices
  module NodeSelector
    extend ActiveSupport::Concern

    # Helper to find a node for this container service's containers.
    #
    # @param [Region] r
    # @param [Node] exclude_node
    def select_node(r, exclude_node = nil)
      if pin_to_node?(r)
        new_node = current_base_node(r, exclude_node)
        # Verify the cache is not stale with an offline node.
        if new_node.online? && !new_node.under_evacuation?
          Rails.cache.delete("#{self.name}_#{r.id}_node")
          new_node = current_base_node(r, exclude_node)
        end
      else
        new_node = r.find_node(package, exclude_node)
      end
      new_node
    end

    # Determine if this container service needs to be pinned to the same node.
    #
    # @param [Region] r The region this container will be placed in.
    # @return [Boolean]
    def pin_to_node?(r)
      return true unless r.has_clustered_storage?
      ##
      # Ensure the region supports clustered storage, and we have no local volumes.
      # If we can migrate, then we don't need to be pinned to a node.
      return false if r.has_clustered_storage? && can_migrate?

      # Containers without a volume don't need to be pinned
      return false if volumes.empty?

      # Default to true
      true
      # return false if r.has_clustered_storage?
      # return true unless container_image.can_scale
      # return false if volumes.empty?
      # true
    end

    ##
    # When pinning a container to a node, find the node to use
    #
    # @param [Region] r
    def current_base_node(r, exclude_node = nil)
      Rails.cache.fetch("#{self.name}_#{r.id}_node", expires_in: 6.hours) do
        base_node = nil
        containers.each do |i|
          next if i.node.nil?
          next if exclude_node && (i.node == exclude_node)
          next unless i.node.online? || i.node.under_evacuation?
          base_node = i.node
          break
        end
        base_node.nil? ? r.find_node(package, exclude_node) : base_node
      end
    end

  end
end
