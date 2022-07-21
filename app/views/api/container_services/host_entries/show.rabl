object false

node :host_entry do
  partial "api/container_services/host_entries/entry", object: @entry
end
