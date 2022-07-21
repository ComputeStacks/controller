attributes :id, :hostname, :ipaddr, :keep_updated, :created_at, :updated_at
node :source_image do |i|
  if i.template
    {
      id: i.template.container_image.id,
      label: i.template.container_image.label
    }
  else
    {}
  end
end
