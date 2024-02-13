attributes :id, :name, :req_state, :stats, :current_state,
           :local_ip, :public_ip, :created_at, :updated_at

attributes deployment_id: :project_id, service_id: :container_service_id

child location: :region do
  attributes :id, :name
end

child region: :availability_zone do
  attributes :id, :name
end

if @logs
  node :logs do
    @logs
  end
end

node :ingress_rules, &:api_ingress_rules

node :on_latest_image, &:latest_image?

node :links do |i|
  {
    container_service: "/api/container_services/#{i.container_service_id}",
    logs: "/api/containers/#{i.id}/logs",
    project: "/api/projects/#{i.deployment&.id}"
  }
end
