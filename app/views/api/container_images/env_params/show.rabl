object false

node :env_param do
  partial "api/container_images/env_params/env", object: @env
end
