object false

node :host_entry do
  partial "api/container_images/custom_host_entries/entry", object: @entry
end
