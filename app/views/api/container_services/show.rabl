object false

node :container_service do
  partial "api/container_services/service", object: @service
end

node :container_image do
  partial "api/container_images/container_image", object: @service.container_image
end
