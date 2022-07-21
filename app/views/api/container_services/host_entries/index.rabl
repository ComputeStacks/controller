object false

node :host_entries do
  @entries.map do |i|
    partial "api/container_services/host_entries/entry", object: i
  end
end
