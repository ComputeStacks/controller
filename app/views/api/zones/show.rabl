object false

node :zone do
  partial "api/zones/zone", object: @dns_zone
end