object false

node :volume_params do
  @volumes.map do |i|
    partial "api/container_images/volume_params/volume", object: i
  end
end