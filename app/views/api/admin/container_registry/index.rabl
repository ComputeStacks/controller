object false

node :container_registries do
  @registries.map do |i|
    partial "api/admin/container_registry/registry", object: i
  end
end
