object false

node :host_entries do
  @entries.map do |i|
    partial "api/container_images/custom_host_entries/entry", object: i
  end
end
