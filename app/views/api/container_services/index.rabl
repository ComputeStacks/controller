object false
if defined?(@images)

  node :container_services do
    @services.map do |i|
      partial "api/container_services/service", object: i
    end
  end

  node :container_images do
    @images.map do |i|
      partial "api/container_images/container_image", object: i
    end
  end
else

  node :container_services do
    @services.map do |i|
      partial "api/container_services/service", object: i
    end
  end

end
