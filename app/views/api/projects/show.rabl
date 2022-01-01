object @deployment => :project
attributes :id, :name, :skip_ssh, :current_state, :created_at, :updated_at
node :container_image_ids do |i|
  i.container_images.uniq.pluck(:id)
end
node :links do |i|
  {
    services: "/api/projects/#{i.id}/services",
    container_images: "/api/projects/#{i.id}/images",
    bastions: "/api/projects/#{i.id}/bastions"
  }
end
node :metadata do |i|
  {
    icons: i.container_images.where(is_load_balancer: false).uniq.collect {|ii| ii.icon_url},
    image_names: i.container_images.where(is_load_balancer: false).uniq.collect {|ii| ii.label}
  }
end
