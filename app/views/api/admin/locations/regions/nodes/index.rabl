object false

node :nodes do
  @nodes.map do |i|
    partial 'api/admin/locations/regions/nodes/node', object: i
  end
end
