object false

node :image_relationships do
  @image_relationships.map do |i|
    partial "api/container_images/image_relationships/rel", object: i
  end
end