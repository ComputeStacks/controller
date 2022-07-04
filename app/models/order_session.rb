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
                :images # Container Images

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
    #    container_id: Integer,
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

    load_state!

    self.project = user.deployments.new(name: default_project_name) if project.nil?
  end

  ##
  # Add a given image, and all dependencies
  #
  # @param [ContainerImage] image
  # @param [Array] volume_overrides Pass volumes we expect to be cloned in this image
  def add_image(image, volume_overrides = [])
    return if image_selected?(image.id)
    to_add = [ image ]
    image.dependencies.each do |i|
      next if image_selected?(i.id)
      unless new_project?
        next if project.container_images.include?(i)
      end
      to_add << i
    end unless skip_dep
    to_add.each do |i|
      settings = {}
      i.setting_params.where(param_type: 'static').each do |ii|
        settings[ii.name] = {
          type: ii.param_type,
          default_value: ii.value,
          value: nil,
          label: ii.label
        }
      end
      vols = []
      i.volumes.each do |ii|
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
        container_id: i.id,
        container_name: i.label,
        params: settings,
        volumes: vols,
        free: i.is_free ? 'yes' : 'no',
        icon: i.icon_url,
        min_cpu: i.min_cpu,
        min_mem: i.min_memory,
        qty: 1
      }
    end
  end

  ##
  # Fix Dependencies
  #
  # Ensure we have all required dependencies.
  #
  # When using `skip_dep`, you should also call this
  # to make sure all dependencies are met prior to handing off to user.
  def add_dependencies!
    images.each do |h|
      image = ContainerImage.find_by id: h[:container_id]
      next if image.nil?
      image.dependencies.each do |i|
        next if image_selected?(i.id)
        unless new_project?
          next if project.container_images.include?(i)
        end
        add_image i
      end
    end
  end

  # Determine whether or not we are creating a new project,
  # or if we're adding containers to an existing one.
  def new_project?
    project&.id.nil?
  end

  def image_selected?(image_id)
    images.detect { |i| i[:container_id] == image_id.to_i }
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
      qty = image[:qty].to_i
      c = {
        image_id: image[:container_id].to_i,
        qty: qty.zero? ? 1 : qty,
        params: [],
        volumes: image[:volumes],
        resources: {}
      }
      c[:resources][:product_id] = image[:package_id] if image[:package_id]
      c[:resources][:cpu] = image[:cpu] if image[:cpu]
      c[:resources][:memory] = image[:mem] if image[:mem]

      image[:params].each do |k, v|
        c[:params] << {
          key: k,
          value: v[:value]
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
      elsif region_validate && ( region_validate.location == location )
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
    "#{NamesGenerator.name("").gsub("-"," ").gsub(/[A-Za-z']+/,&:capitalize)} (#{Date.today.strftime("%Y%m%d")})"
  end

end
