object false

node :ingress_params do
  @ingress_params.map do |i|
    partial "api/container_images/ingress_params/ingress", object: i
  end
end