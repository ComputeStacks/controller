object false

node :setting_params do
  @settings.map do |i|
    partial "api/container_images/setting_params/setting", object: i
  end
end