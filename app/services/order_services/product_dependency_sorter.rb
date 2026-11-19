module OrderServices
  ##
  # Put an order's products in the order they must be provisioned: a product whose image is a
  # dependency of another product's image comes before it.
  #
  # Dependencies are matched the same way `ContainerServices::ServiceConfig#init_link!` links
  # them -- by image id OR by role -- so the database an image requires exists before the
  # image that requires it is built. Without this, an order for [wordpress, mariadb, redis]
  # built WordPress and Redis first, and a failed database left a site that could never work.
  #
  # Stable: products with no dependency relation keep their original relative order. Products
  # that depend on each other in a cycle keep their original relative order too, and a product
  # whose image cannot be resolved simply has no relations. Never raises.
  #
  # Returns the same product objects (not copies); the order loop removes them by identity.
  class ProductDependencySorter
    attr_reader :products

    # @param products [Array<Hash>] `order.data[:raw_order]`
    def initialize(products)
      @products = Array(products)
    end

    # @return [Array<Hash>]
    def perform
      return products.dup if products.length < 2
      images = products.map { |product| image_for(product) }
      sorted_indexes(edges(images)).map { |i| products[i] }
    rescue => e
      ExceptionAlertService.new(e, "6c0f3e9d2b7a4158").perform
      products.dup
    end

    private

    # @return [ContainerImage, nil]
    def image_for(product)
      return nil unless product.is_a?(Hash)
      return nil unless (product[:product_type] || product["product_type"]) == "container"
      variant_id = product[:image_variant_id] || product["image_variant_id"]
      return nil if variant_id.blank?
      ContainerImage::ImageVariant.find_by(id: variant_id)&.container_image
    end

    ##
    # `before[j]` holds every product index that must be provisioned before product j.
    #
    # @return [Array<Array<Integer>>]
    def edges(images)
      before = Array.new(products.length) { [] }
      images.each_with_index do |image, j|
        next if image.nil?
        image.dependencies.each do |dep|
          images.each_with_index do |candidate, i|
            next if i == j || candidate.nil?
            if candidate.id == dep.id || (dep.role.present? && candidate.role == dep.role)
              before[j] << i
            end
          end
        end
      end
      before.map(&:uniq)
    end

    ##
    # Collapse each cycle into one group (whose members keep their original order), then
    # repeatedly emit the ready group with the lowest original index.
    #
    # @return [Array<Integer>]
    def sorted_indexes(before)
      n = products.length
      reach = (0...n).map { |j| reachable(j, before) } # products that must precede j, transitively
      group_of = (0...n).map { |j| (0...n).select { |i| i == j || (reach[j].include?(i) && reach[i].include?(j)) } }
      groups = group_of.uniq
      sorted = []
      until groups.empty?
        ready = groups.find do |group|
          group.all? { |j| (before[j] - group).all? { |i| sorted.include?(i) } }
        end
        ready ||= groups.first # unreachable; guards against a logic error looping forever
        sorted.concat(ready)
        groups.delete(ready)
      end
      sorted
    end

    # @return [Array<Integer>]
    def reachable(start, before)
      seen = []
      stack = before[start].dup
      until stack.empty?
        i = stack.pop
        next if seen.include?(i)
        seen << i
        stack.concat(before[i])
      end
      seen
    end
  end
end
