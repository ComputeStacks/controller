module UserCanDo
  extend ActiveSupport::Concern

  def current_quota(refresh_cache = false)
    user_group.current_quota(self, refresh_cache)
  end

  def can_order_containers?(qty = 1)
    current_quota(true).dig(:containers, :available) >= qty
  end

  def can_order_cr?(qty = 1)
    current_quota(true).dig(:cr, :available) >= qty
  end

  def can_order_zones?(qty = 1)
    current_quota(true).dig(:dns_zones, :available) >= qty
  end

  ##
  # Can this user force local storage on a volume?
  #
  # @return [Boolean]
  def can_force_local_storage?
    return false unless Feature.using_clustered_storage?
    is_admin || ( user_group.allow_local_volume && user_group.regions.where(volume_backend: 'nfs').exists? )
  end

end
