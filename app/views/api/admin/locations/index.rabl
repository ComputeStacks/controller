object false

node :locations do
  @locations.map do |i|
    partial 'api/admin/locations/location', object: i
  end
end
