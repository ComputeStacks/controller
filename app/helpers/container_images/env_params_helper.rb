module ContainerImages
  module EnvParamsHelper

    def new_container_image_env_path(image)
      return nil if image.nil?
      "#{container_image_path(image)}/env_params/new"
    end

    def edit_container_image_env_path(env)
      return "/container_images" if env.nil?
      "#{container_image_env_path(env)}/edit"
    end

    def container_image_env_path(env)
      return "/container_images" if env.nil?
      "#{container_image_path(env.container_image)}/env_params/#{env.id}"
    end

  end
end