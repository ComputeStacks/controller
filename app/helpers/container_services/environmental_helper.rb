module ContainerServices
  module EnvironmentalHelper

    def new_container_service_environmental_path(service)
      "/container_services/#{service.id}/environmental/new"
    end

    def edit_container_service_environmental_path(env)
      "#{container_service_environmental_path(env)}/edit"
    end

    def container_service_environmental_path(env)
      "/container_services/#{env.container_service.id}/environmental/#{env.id}"
    end

  end
end