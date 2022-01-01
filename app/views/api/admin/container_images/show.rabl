object false

node :container_image do
  partial "api/admin/container_images/container_image", object: @container_image
end
