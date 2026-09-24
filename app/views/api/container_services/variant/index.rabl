object false
node :image_variants do
  @service.container_image.image_variants.map do |i|
    partial "api/container_services/variant/variant", object: i, locals: {service: @service}
  end
end
