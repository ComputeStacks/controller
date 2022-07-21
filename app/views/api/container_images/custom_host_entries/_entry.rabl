attributes :id, :hostname, :created_at, :updated_at
node :source_image do |i|
  if i.source_image
    {
      id: i.source_image.id,
      label: i.source_image.label
    }
  else
    {}
  end
end
