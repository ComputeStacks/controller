object false

node :container_image_provider do
  partial "api/container_image_providers/image_provider", object: @provider
end
