object false

node :regions do
  @regions.map do |i|
    partial 'api/admin/locations/regions/region', object: i
  end
end
