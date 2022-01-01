object false

node :container_registry do
  partial "api/admin/container_registry/registry", object: @registry
end

