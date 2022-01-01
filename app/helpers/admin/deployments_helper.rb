module Admin::DeploymentsHelper

  def admin_deployments_path(deployment)
    "/admin/deployments/#{deployment.id}-#{deployment.name.parameterize}"
  end

  # @param [Deployment::EventLog] event
  def admin_deployment_event(event)
    data = event.description
    event.containers.each do |i|
      data = data.gsub("#{i.name}", "<a href='#{admin_containers_path(i)}'>#{i.name}</a>")
    end
    event.container_services.each do |i|
      data = data.gsub("[#{i.label}]", "[<a href='#{admin_container_service_path(i)}'>#{i.label}</a>]")
    end
    data
  end

end
