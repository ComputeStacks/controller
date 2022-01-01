object false

node :ingress_param do
  partial "api/container_images/ingress_params/ingress", object: @ingress_param
end
