object false

node :container_image_providers do
  @providers.map do |i|
    partial "api/container_image_providers/image_provider", object: i
  end
end