object false

node :certificate do
  partial "api/container_services/ssl/cert", object: @event
end

