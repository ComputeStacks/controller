object false

node :container_images do
  @container_images.map do |image|
    partial "api/container_images/container_image", object: image
  end
end
