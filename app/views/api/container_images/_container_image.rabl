attributes :id,
           :active,
           :can_scale,
           :command,
           :container_image_provider_id,
           :description,
           :icon_url,
           :is_free,
           :label,
           :min_cpu,
           :min_memory,
           :registry_custom,
           :registry_image_path,
           :registry_auth,
           :registry_username,
           :is_load_balancer,
           :role,
           :category,
           :labels,
           :validated_tag,
           :validated_tag_updated,
           :created_at,
           :updated_at

node :system_image do |i|
  i.user.nil?
end
node :available_vars do |i|
  i.available_vars
end
child :env_params do
  extends 'api/container_images/env_params/_env'
end
child :host_entries do
  extends 'api/container_images/custom_host_entries/_entry'
end
child :setting_params do
  extends 'api/container_images/setting_params/_setting'
end
child :ingress_params do
  extends 'api/container_images/ingress_params/_ingress'
end
child :volumes do
  extends 'api/container_images/volume_params/_volume'
end
node :required_containers do |i|
  i.dependencies.pluck(:id)
end
node :required_by do |i|
  i.parent_containers.pluck(:id)
end
child :image_variants do
  extends 'api/container_images/image_variants/_variant'
end

node :links do |i|
  {
    container_image_provider: "/api/container_image_providers/#{i.container_image_provider_id}"
  }
end
