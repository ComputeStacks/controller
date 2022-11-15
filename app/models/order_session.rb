# OrderSession service
#
# @attr [integer] id Will become the Order ID (uuid)
# @attr [Order] order nil if order does not exist yet.
class OrderSession

  attr_accessor :id,
                :user,
                :order,
                :project,
                :location,
                :skip_dep, # dont add dependency images
                :skip_ssh, # defaults to false
                :region, # Used to find prices
                :images, # Container Images
                :collections # image collections

  def initialize(user, id = nil)
    return nil unless user.is_a? User

    self.id = id.nil? ? SecureRandom.uuid : id
    self.project = nil
    self.location = nil
    self.region = nil # Dynamically loaded by location
    self.user = user
    self.skip_ssh = false

    # When adding images programmatically, there are times we
    # don't want dependent images to be added because we'll get them later.
    self.skip_dep = false

    # Images
    #
    # [
    #   {
    #    image_id: Integer,
    #    image_variant_id: Integer,
    #    container_name: String,
    #    package_id: Integer,
    #    label: String,
    #    free: String, #<yes|no>
    #    icon: String, # url
    #    cpu: Float,
    #    mem: Integer,
    #    min_cpu: Float,
    #    min_mem: Integer,
    #    qty: Integer,
    #    params: {
    #      String: {
    #        type: String,
    #        default_value: String,
    #        value: String,
    #        label: String
    #      }
    #    }
    #  }
    # ]
    self.images = []
    self.collections = []

    load_state!

    self.project = user.deployments.new(name: default_project_name) if project.nil?
  end

  ##
  # Add a given image, and all dependencies
  #
  # @param [ContainerImage] image
  # @param [Hash] opts
  #     {
  #       volume_overrides: [],
  #       source: ""
  #      }
  def add_image(image_variant, opts = {})
    return if image_variant.nil?
    return if image_variant_selected?(image_variant.id)
    images.each do |i|
      if i[:image_id] == image_variant.container_image.id
        images.delete i
      end
    end
    opts = opts.with_indifferent_access
    volume_overrides = opts[:volume_overrides] ? opts[:volume_overrides] : []
    collection_id = opts[:collection_id]
    # Container Source
    source_csrn = opts[:source]
    source_service = source_csrn.blank? ? nil : Csrn.locate(opts[:source])
    source = if source_service && source_service.is_a?(Deployment::ContainerService)
               source_service.can_view?(user) ? source_service : nil
             else
               nil
             end
    to_add = [ image_variant ]
    source_settings = {}
    if source
      source.setting_params.each do |ii|
        source_settings[ii.name] = ii.decrypted_value
      end
    end
    to_add.each do |i|
      settings = {}
      i.container_image.setting_params.each do |ii|
        next if ii.param_type == 'password' && source.nil?
        settings[ii.name] = {
          type: ii.param_type,
          default_value: ii.value,
          value: source_settings[ii.name],
          label: ii.label
        }
      end
      vols = []
      i.container_image.volumes.each do |ii|
        cloned_vol = volume_overrides.select { |vo| vo[:mount_path] == ii.mount_path }[0]
        vol_action = if cloned_vol
                       cloned_vol[:action]
                     else
                       ii.source_volume ? 'mount' : 'create'
                     end
        vol_source = if cloned_vol
                       cloned_vol[:source]
                     else
                       ii.source_volume&.csrn
                     end
        vols << {
          csrn: ii.csrn,
          label: ii.label,
          mount_path: ii.mount_path,
          action: vol_action,
          source: vol_source,
          mount_ro: cloned_vol ? cloned_vol[:mount_ro] : ii.mount_ro,
          snapshot: nil # archive ID
        }
      end
      images << {
        label: "",
        image_id: i.container_image.id,
        image_variant_id: i.id,
        source: source ? source_csrn : nil,
        container_name: i.friendly_name,
        params: settings,
        volumes: vols,
        free: i.container_image.is_free ? 'yes' : 'no',
        min_cpu: i.container_image.min_cpu,
        min_mem: i.container_image.min_memory,
        qty: 1,
        collection_id: collection_id
      }
    end
    add_dependencies!(opts) unless skip_dep
  end

  def add_collection(collection_id)
    collection = ContainerImageCollection.find_by id: collection_id
    return if collection.nil?

    # for images that have defined a non-standard variant (e.g. mariadb 10.5 instead of the default),
    # gather those here and reference them later during the _add each image in collection_ process.
    h = {} # { image_id => variant }
    collection.container_images.each do |i|
      i.dependency_parents.each do |i_dep|
        variant = i_dep.default_variant ? i_dep.default_variant : i_dep.dependency.default_variant
        h[i_dep.dependency.id] = variant
      end
    end

    collection.container_images.each do |i|
      next if image_selected? i.id
      variant = h[i.id].nil? ? i.default_variant : h[i.id]
      add_image variant, { collection_id: collection.id }
    end
  end

  ##
  # Fix Dependencies
  #
  # Ensure we have all required dependencies.
  #
  # When using `skip_dep`, you should also call this directly,
  # otherwise it will be automatically called when adding an image.
  #
  # This will also add an image's dependency dependencies.
  def add_dependencies!(opts = {})
    images.each do |h|
      image = ContainerImage.find_by id: h[:image_id]
      next if image.nil?
      image.dependency_parents.each do |i_dep|
        next if i_dep.container_image.nil?
        next if image_selected?(i_dep.dependency.id)
        unless new_project?
          next if project.container_images.include?(i_dep.dependency)
        end
        variant = i_dep.default_variant ? i_dep.default_variant : i_dep.dependency.default_variant
        add_image variant, opts
      end
    end
  end

  # Determine whether or not we are creating a new project,
  # or if we're adding containers to an existing one.
  def new_project?
    project&.id.nil?
  end

  def image_variant_selected?(image_variant_id)
    images.detect { |i| i[:image_variant_id] == image_variant_id.to_i }
  end

  def image_selected?(image_id)
    images.detect { |i| i[:image_id] == image_id.to_i }
  end

  # For displaying selected image on order form
  def order_image_selected?(image_id)
    return false unless image_selected?(image_id)
    i = images.select { |i| i[:image_id] == image_id.to_i }
    return false unless i[0][:collection_id].nil?
    true
  end

  def collection_selected?(collection_id)
    images.detect { |i| i[:collection_id] == collection_id.to_i }
  end

  # Given the current set of images, can we skip
  # the param/package selection screen?
  def skip_to_confirmation?
    skip = true
    images.each do |i|
      next if i[:params].empty? && i[:free] == 'yes'
      skip = false
    end
    skip
  end

  # Generate a list of packages for choosing a node
  def requested_packages
    p = []
    images.each do |image|
      next if image[:package_id].nil?
      prod = Product.find_by id: image[:package_id]
      next if prod.nil? || prod.package.nil?
      p << prod.package
    end
    p
  end

  # Build the order object for saving!
  def to_order
    order_data = {
      id: id,
      project_name: project&.name,
      skip_ssh: skip_ssh,
      location_id: location&.id,
      containers: []
    }

    # Only include the `:id` element for existing projects
    order_data[:project_id] = project.id if project&.id

    images.each do |image|
      c = {
        image_id: image[:image_id].to_i,
        image_variant: image[:image_variant_id].to_i,
        source: image[:source], # Deployment::ContainerService.csrn
        params: [],
        volumes: image[:volumes],
        resources: {}
      }
      c[:qty] = image[:qty].to_i.zero? ? 1 : image[:qty].to_i
      c[:resources][:product_id] = image[:package_id] if image[:package_id]
      c[:resources][:cpu] = image[:cpu] if image[:cpu]
      c[:resources][:memory] = image[:mem] if image[:mem]

      image[:params].each do |k, v|
        c[:params] << {
          key: k,
          value: v[:value],
          type: v[:type]
        }
      end

      order_data[:containers] << c
    end
    order_data
  end

  def save
    Rails.cache.write("order_#{id}", to_hash, expires_in: 4.hours)
  end

  def destroy
    Rails.cache.delete "order_#{id}"
  end

  private

  # Generate a hash to save to redis
  def to_hash
    {
      id: id,
      user_id: user&.id,
      order_id: order&.id,
      project: {
        id: project&.id,
        name: project&.name,
        skip_ssh: skip_ssh
      },
      location_id: location&.id,
      region_id: region&.id,
      images: images
    }
  end

  def load_state!
    d = Rails.cache.read("order_#{id}")
    return if d.nil?
    d = d.symbolize_keys
    return destroy unless valid_cache_hash? d

    self.id = d[:id]

    # If this fails, then stop loading!
    # This is because the order can not be modified anymore!
    return destroy unless ensure_unique!

    self.order = Order.find_by(id: id)

    self.user = User.find_by(id: d[:user_id])

    self.project = Deployment.find_for user, id: d[:project][:id]
    self.project = user.deployments.new(name: d[:project][:name]) if project.nil?

    if project&.id
      self.location = project.locations.first
      self.region = project.regions.first
    else
      self.location = Location.find_by id: d[:location_id]
      region_validate = d[:region_id].blank? ? nil : Region.find_by(id: d[:region_id])
      if location && (region.nil? && region_validate.nil?)

        image_count = d[:images] ? (d[:images].count + 1) : 2 # add 1 additional for the SFTP container

        self.region = location.next_region requested_packages, user, image_count
      elsif region_validate && (region_validate.location == location)
        self.region = region_validate
      end
    end
    self.images = d[:images]
  end

  def ensure_unique!
    if Order.where("id = ? AND status != 'open'", id).exists?
      self.id = SecureRandom.uuid
      false
    end
    true
  end

  # Ensure the data we are getting from the cache is valid
  def valid_cache_hash?(data)
    return false unless (
      [
        :id,
        :user_id,
        :order_id,
        :project,
        :images,
        :location_id
      ] - data.keys).empty?

    return false unless ([:id, :name] - data[:project].keys).empty?
    return false if data[:user_id].blank? # We require this!
    true
  end

  def default_project_name
    "#{NamesGenerator.name("").gsub("-", " ").gsub(/[A-Za-z']+/, &:capitalize)} (#{Date.today.strftime("%Y%m%d")})"
  end

end
