object false

node :image_collections do
  @collections.map do |i|
    partial "api/image_collections/collection", object: i
  end
end
