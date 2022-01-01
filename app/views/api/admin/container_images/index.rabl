object false

node :container_images do
  @container_images.map do |i|
    partial "api/admin/container_images/container_image", object: i
  end
end
