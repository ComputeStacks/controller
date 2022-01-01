object false

node :volume_param do
  partial "api/container_images/volume_params/volume", object: @volume
end
