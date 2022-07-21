object false

node :env_params do
  @envs.map do |i|
    partial "api/container_images/env_params/env", object: i
  end
end
