attributes :id, :label, :is_default
node :active do |i|
  locals[:service].image_variant == i
end