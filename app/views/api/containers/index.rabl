object false

node :containers do
  @containers.map do |i|
    partial "api/containers/container", object: i
  end
end
