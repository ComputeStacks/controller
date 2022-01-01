object false

node :certificates do
  @certificates.map do |i|
    partial "api/container_services/ssl/cert", object: i
  end
end