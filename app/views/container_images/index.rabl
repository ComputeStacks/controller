collection @images, root: 'data', object_root: false
attributes :id

node :name do |i|
  %Q(#{table_image_icon(i)} <a href="/container_images/#{i.id}">#{i.label}</a>)
end

node :image do |i|
  i.container_registry ? %Q(<a href="/container_registry/#{i.container_registry.id}">#{i.container_registry.label}</a>) : i.registry_image_path
end

node :button_group do |i|
  image_table_buttons i
end

node :owner do |i|
  i.user.full_name
end
