object false

node :container_registry do
  partial "api/container_registry/registry", object: @registry
end

