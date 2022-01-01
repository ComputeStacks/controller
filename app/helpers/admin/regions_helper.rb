module Admin::RegionsHelper

  def admin_regions_url(region)
    "/admin/regions/#{region.id}-#{region.name.parameterize}"
  end

end
